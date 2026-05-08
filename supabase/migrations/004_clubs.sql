-- 004_clubs.sql
-- 동호회/클럽 디렉토리 (관리자 등록 전용, 가입·게시판 없음)

create table public.clubs (
  id uuid primary key default gen_random_uuid(),
  sport sport not null,

  name text not null,
  region text,           -- 시·도
  address text,          -- 상세 주소
  contact text,          -- 전화/카톡/오픈채팅
  website text,
  description text,

  active boolean not null default true,
  created_by uuid references public.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index clubs_sport_region_idx on public.clubs (sport, region) where active;

create trigger clubs_touch_updated_at
  before update on public.clubs
  for each row execute function public.touch_updated_at();

-- =========================
-- RLS: 인증 사용자 read, 관리자만 write
-- =========================
alter table public.clubs enable row level security;

create policy clubs_authenticated_read on public.clubs
  for select using (auth.role() = 'authenticated' and active);

create policy clubs_admin_all on public.clubs
  for all using (public.is_admin()) with check (public.is_admin());
