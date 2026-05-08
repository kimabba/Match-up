-- 003_tournaments.sql
-- 대회 + 즐겨찾기 + 사용자 제보(검수) + pgvector 임베딩

create type tournament_status as enum ('draft', 'published', 'closed');

-- =========================
-- tournaments
-- =========================
create table public.tournaments (
  id uuid primary key default gen_random_uuid(),
  sport sport not null,

  title text not null,
  organizer text,
  description text,

  start_date date not null,
  end_date date,
  application_deadline date,

  region text,           -- 시·도 단위 (예: "광주", "전남")
  location text,         -- 상세 장소

  -- 출전 가능 등급 (배열). tennis: rookie..div1, futsal: beginner..advanced
  eligible_grades text[] not null default '{}'::text[],

  entry_fee integer,
  prize text,
  format text,           -- 단·복식, 토너먼트, 리그 등

  source_url text,
  source text,           -- 'manual', 'crawl-tennis-gwangju', 'user_submission' 등

  status tournament_status not null default 'draft',

  -- 사용자 제보·관리자 검수
  submitted_by uuid references public.users(id) on delete set null,
  approved_by uuid references public.users(id) on delete set null,
  approved_at timestamptz,
  rejection_reason text,

  -- 의미 기반 검색용 임베딩
  embedding vector(768),
  embedding_updated_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index tournaments_sport_status_date_idx
  on public.tournaments (sport, status, start_date desc);

create index tournaments_region_idx on public.tournaments (region) where status = 'published';

create index tournaments_eligible_grades_gin
  on public.tournaments using gin (eligible_grades) where status = 'published';

-- 크롤러 중복 방지 (같은 source + 같은 source_url 은 1개)
create unique index tournaments_source_url_unique
  on public.tournaments (source, source_url) where source_url is not null;

-- HNSW 벡터 인덱스 (cosine), published 만 대상으로 partial 인덱스
create index tournaments_embedding_hnsw_idx
  on public.tournaments using hnsw (embedding vector_cosine_ops)
  where status = 'published' and embedding is not null;

create trigger tournaments_touch_updated_at
  before update on public.tournaments
  for each row execute function public.touch_updated_at();

-- 대회 내용이 바뀌면 임베딩 무효화 → embed-pending 워커가 재계산
create or replace function public.invalidate_tournament_embedding()
returns trigger language plpgsql as $$
begin
  if (old.title is distinct from new.title)
     or (old.description is distinct from new.description)
     or (old.region is distinct from new.region)
     or (old.format is distinct from new.format)
     or (old.organizer is distinct from new.organizer)
  then
    new.embedding := null;
    new.embedding_updated_at := null;
  end if;
  return new;
end;
$$;

create trigger tournaments_invalidate_embedding
  before update on public.tournaments
  for each row execute function public.invalidate_tournament_embedding();

-- =========================
-- tournament_favorites
-- =========================
create table public.tournament_favorites (
  user_id uuid not null references public.users(id) on delete cascade,
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, tournament_id)
);

create index tournament_favorites_tid_idx on public.tournament_favorites (tournament_id);

-- =========================
-- RLS
-- =========================
alter table public.tournaments enable row level security;
alter table public.tournament_favorites enable row level security;

-- tournaments: 인증 사용자는 published 만 read, 본인 제보 draft 도 read,
--              관리자 전체 read/write
create policy tournaments_published_read on public.tournaments
  for select using (
    status = 'published'
    or auth.uid() = submitted_by
    or public.is_admin()
  );

-- 사용자 제보: 누구나 insert 가능하지만 status='draft', submitted_by=auth.uid() 강제
create policy tournaments_user_submit on public.tournaments
  for insert with check (
    auth.uid() = submitted_by
    and status = 'draft'
    and approved_by is null
  );

-- 본인 제보(draft)는 본인이 수정/삭제 가능
create policy tournaments_self_draft_update on public.tournaments
  for update using (
    auth.uid() = submitted_by and status = 'draft'
  ) with check (
    auth.uid() = submitted_by and status = 'draft'
  );

create policy tournaments_self_draft_delete on public.tournaments
  for delete using (
    auth.uid() = submitted_by and status = 'draft'
  );

-- 관리자 전권
create policy tournaments_admin_all on public.tournaments
  for all using (public.is_admin()) with check (public.is_admin());

-- tournament_favorites: 본인만
create policy tournament_favorites_self on public.tournament_favorites
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy tournament_favorites_admin_read on public.tournament_favorites
  for select using (public.is_admin());

-- =========================
-- RPC: 사용자 등급으로 출전 가능한 대회 조회
-- =========================
create or replace function public.tournaments_for_user(
  p_user_id uuid,
  p_sport sport default null,
  p_region text default null,
  p_date_from date default null,
  p_date_to date default null,
  p_only_my_grade boolean default true,
  p_query text default null,
  p_limit int default 50,
  p_offset int default 0
)
returns setof public.tournaments
language sql
stable
security invoker
as $$
  select t.*
  from public.tournaments t
  where t.status = 'published'
    and (p_sport is null or t.sport = p_sport)
    and (p_region is null or t.region = p_region)
    and (p_date_from is null or t.start_date >= p_date_from)
    and (p_date_to is null or t.start_date <= p_date_to)
    and (
      p_query is null
      or t.title ilike '%' || p_query || '%'
      or coalesce(t.organizer, '') ilike '%' || p_query || '%'
      or coalesce(t.description, '') ilike '%' || p_query || '%'
    )
    and (
      not p_only_my_grade
      or exists (
        select 1 from public.user_sports us
        where us.user_id = p_user_id
          and us.sport = t.sport
          and us.grade = any(t.eligible_grades)
      )
    )
  order by t.start_date asc, t.created_at desc
  limit greatest(p_limit, 0)
  offset greatest(p_offset, 0);
$$;

grant execute on function public.tournaments_for_user(uuid, sport, text, date, date, boolean, text, int, int) to authenticated;

-- =========================
-- RPC: 의미 기반 대회 검색 (pgvector)
-- =========================
create or replace function public.tournaments_semantic_search(
  p_user_id uuid,
  p_query_embedding vector(768),
  p_only_my_grade boolean default true,
  p_match_count int default 10
)
returns table (
  id uuid,
  sport sport,
  title text,
  start_date date,
  region text,
  eligible_grades text[],
  similarity real
)
language sql
stable
security invoker
as $$
  select
    t.id,
    t.sport,
    t.title,
    t.start_date,
    t.region,
    t.eligible_grades,
    (1 - (t.embedding <=> p_query_embedding))::real as similarity
  from public.tournaments t
  where t.status = 'published'
    and t.embedding is not null
    and (
      not p_only_my_grade
      or exists (
        select 1 from public.user_sports us
        where us.user_id = p_user_id
          and us.sport = t.sport
          and us.grade = any(t.eligible_grades)
      )
    )
  order by t.embedding <=> p_query_embedding
  limit greatest(p_match_count, 1);
$$;

grant execute on function public.tournaments_semantic_search(uuid, vector, boolean, int) to authenticated;
