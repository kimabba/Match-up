-- 013_qa_cache.sql
-- Semantic Q&A cache (Day 2, LLM 비용 절감 계획).
--
-- 사용자 채팅 질문을 임베딩으로 캐싱해 동일·유사 질문에 LLM 호출 없이 응답한다.
-- Edge Function (`chat/index.ts`) 가 service_role 키로만 조회/적재한다.
-- 사용자 컨텍스트 (종목·등급·협회) 별로 격리하기 위해 `user_context_hash` 를 캐시 키에 포함한다.

create extension if not exists vector;

create table if not exists public.qa_cache (
  id uuid primary key default gen_random_uuid(),

  -- 원본 질문 (디버깅·중복 점검용)
  question_text text not null,

  -- gemini-embedding-001 (outputDimensionality=768, RETRIEVAL_QUERY task)
  question_embedding vector(768) not null,

  -- 캐시된 응답 본문
  answer_text text not null,

  -- chat/index.ts 의 dbCitations + ruleCitations 형식과 동일한 jsonb 배열
  -- 예: [{ "type": "db", "source": "tournaments", "id": "...", "title": "..." }]
  citations jsonb not null default '[]'::jsonb,

  -- 사용자 컨텍스트 격리용. SHA-256(JSON({sports, orgs})) 16진 문자열.
  -- 다른 컨텍스트 사용자의 캐시는 절대 매칭되지 않음.
  user_context_hash text not null,

  hit_count int not null default 0,

  created_at timestamptz not null default now(),
  -- 기본 24h TTL. application 단에서 INSERT 시 명시적으로 설정.
  ttl_expires_at timestamptz not null
);

comment on table public.qa_cache is
  'Semantic cache for chat Q&A. service_role only (Edge Function 전용).';
comment on column public.qa_cache.user_context_hash is
  'SHA-256 of normalized user profile (sports + orgs). 캐시 격리 키.';
comment on column public.qa_cache.ttl_expires_at is
  '캐시 만료 시각. 기본 created_at + 24h. lookup 시 ttl 살아있는 행만 매칭.';

-- HNSW 인덱스 (cosine). published 임베딩이 있는 행만 대상.
-- (qa_cache 행은 항상 embedding 이 not null 이므로 partial 조건 불필요)
create index if not exists qa_cache_embedding_hnsw_idx
  on public.qa_cache using hnsw (question_embedding vector_cosine_ops);

-- 컨텍스트 + TTL 빠른 필터링용
create index if not exists qa_cache_ctx_ttl_idx
  on public.qa_cache (user_context_hash, ttl_expires_at);

-- 중복 INSERT 방지용 unique index.
-- 같은 (user_context_hash, question_text) 가 동시 요청에서 두 번 들어오면 둘 다 MISS → 둘 다 INSERT → 중복 행.
-- PostgreSQL 은 unique CONSTRAINT 에 expression 을 못 쓰므로 unique INDEX 로 표현.
-- INSERT 시 ON CONFLICT DO NOTHING 으로 race 안전 보장 (qa_cache_insert_if_absent RPC 참조).
create unique index if not exists qa_cache_unique_question_per_context
  on public.qa_cache (user_context_hash, md5(question_text));

-- =========================
-- RLS
-- =========================
alter table public.qa_cache enable row level security;

-- service_role 만 전권. 인증/익명 사용자는 직접 접근 불가.
-- (Edge Function 이 service_role 키로 호출하므로 클라이언트 노출 불필요)
-- 이미 존재할 경우를 대비해 drop 후 재생성 (idempotent).
drop policy if exists qa_cache_service_role_all on public.qa_cache;
create policy qa_cache_service_role_all on public.qa_cache
  for all
  to service_role
  using (true)
  with check (true);

-- =========================
-- RPC: 캐시 lookup (cosine similarity ≥ threshold, TTL 살아있음, context 일치)
-- =========================
create or replace function public.qa_cache_lookup(
  p_query_embedding vector(768),
  p_user_context_hash text,
  p_threshold real default 0.92
)
returns table (
  id uuid,
  answer_text text,
  citations jsonb,
  similarity real
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id,
    c.answer_text,
    c.citations,
    (1 - (c.question_embedding <=> p_query_embedding))::real as similarity
  from public.qa_cache c
  where c.user_context_hash = p_user_context_hash
    and c.ttl_expires_at > now()
    and (1 - (c.question_embedding <=> p_query_embedding)) >= p_threshold
  order by c.question_embedding <=> p_query_embedding
  limit 1;
$$;

-- service_role 만 호출 가능. authenticated/anon 에는 grant 하지 않음.
revoke all on function public.qa_cache_lookup(vector, text, real) from public;
grant execute on function public.qa_cache_lookup(vector, text, real) to service_role;

-- =========================
-- RPC: race-safe INSERT (ON CONFLICT DO NOTHING)
-- =========================
-- 동시 요청 race condition 대응. qa_cache_unique_question_per_context 인덱스에 의존.
-- PostgREST 의 upsert + expression index 조합이 불안정하므로 RPC 로 명시.
-- 충돌 시 행 없이 NULL 반환 (정상 동작 — 호출 측은 INSERT 성공 여부만 신경쓰지 않음).
create or replace function public.qa_cache_insert_if_absent(
  p_question_text text,
  p_question_embedding vector(768),
  p_answer_text text,
  p_citations jsonb,
  p_user_context_hash text,
  p_ttl_expires_at timestamptz
)
returns uuid
language sql
security definer
set search_path = public
as $$
  insert into public.qa_cache (
    question_text,
    question_embedding,
    answer_text,
    citations,
    user_context_hash,
    ttl_expires_at
  )
  values (
    p_question_text,
    p_question_embedding,
    p_answer_text,
    p_citations,
    p_user_context_hash,
    p_ttl_expires_at
  )
  -- expression index 매칭. unique index (user_context_hash, md5(question_text)) 와 일치해야 한다.
  on conflict (user_context_hash, md5(question_text)) do nothing
  returning id;
$$;

revoke all on function public.qa_cache_insert_if_absent(text, vector, text, jsonb, text, timestamptz) from public;
grant execute on function public.qa_cache_insert_if_absent(text, vector, text, jsonb, text, timestamptz) to service_role;
