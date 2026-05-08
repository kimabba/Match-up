-- 005_chat_rules.sql
-- 챗봇 대화 이력(영구 저장) + 룰북 콘텐츠(+pgvector)

create type chat_role as enum ('user', 'assistant');

-- =========================
-- chat_messages : 영구 저장
-- =========================
create table public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  conversation_id uuid not null,         -- 대화 단위 묶음
  role chat_role not null,
  content text not null,
  citations jsonb not null default '[]'::jsonb,   -- [{type:'db'|'web', id?, url?, title?}, ...]
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index chat_messages_user_conv_idx
  on public.chat_messages (user_id, conversation_id, created_at);

create index chat_messages_user_recent_idx
  on public.chat_messages (user_id, created_at desc);

-- =========================
-- rule_articles : 룰북 (관리자 작성, 의미 검색용 임베딩)
-- =========================
create table public.rule_articles (
  id uuid primary key default gen_random_uuid(),
  sport sport not null,
  category text not null,            -- 예: '서브', '발리', '라인', '파울'
  title text not null,
  body text not null,                -- markdown
  order_idx integer not null default 0,
  published boolean not null default true,

  embedding vector(768),
  embedding_updated_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index rule_articles_sport_cat_idx
  on public.rule_articles (sport, category, order_idx) where published;

create index rule_articles_embedding_hnsw_idx
  on public.rule_articles using hnsw (embedding vector_cosine_ops)
  where published and embedding is not null;

create trigger rule_articles_touch_updated_at
  before update on public.rule_articles
  for each row execute function public.touch_updated_at();

create or replace function public.invalidate_rule_embedding()
returns trigger language plpgsql as $$
begin
  if (old.title is distinct from new.title) or (old.body is distinct from new.body) then
    new.embedding := null;
    new.embedding_updated_at := null;
  end if;
  return new;
end;
$$;

create trigger rule_articles_invalidate_embedding
  before update on public.rule_articles
  for each row execute function public.invalidate_rule_embedding();

-- =========================
-- RLS
-- =========================
alter table public.chat_messages enable row level security;
alter table public.rule_articles enable row level security;

-- chat_messages: 본인만
create policy chat_messages_self on public.chat_messages
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy chat_messages_admin_read on public.chat_messages
  for select using (public.is_admin());

-- rule_articles: 인증 read, 관리자 write
create policy rule_articles_authenticated_read on public.rule_articles
  for select using (auth.role() = 'authenticated' and published);

create policy rule_articles_admin_all on public.rule_articles
  for all using (public.is_admin()) with check (public.is_admin());

-- =========================
-- RPC: 룰북 의미 기반 검색
-- =========================
create or replace function public.rules_semantic_search(
  p_query_embedding vector(768),
  p_sport sport default null,
  p_match_count int default 5
)
returns table (
  id uuid,
  sport sport,
  category text,
  title text,
  body text,
  similarity real
)
language sql
stable
security invoker
as $$
  select
    r.id,
    r.sport,
    r.category,
    r.title,
    r.body,
    (1 - (r.embedding <=> p_query_embedding))::real as similarity
  from public.rule_articles r
  where r.published
    and r.embedding is not null
    and (p_sport is null or r.sport = p_sport)
  order by r.embedding <=> p_query_embedding
  limit greatest(p_match_count, 1);
$$;

grant execute on function public.rules_semantic_search(vector, sport, int) to authenticated;
