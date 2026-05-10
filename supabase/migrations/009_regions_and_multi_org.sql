-- 009_regions_and_multi_org.sql
-- 한국 동호인 테니스 도메인 정합성 보강
--   1) regions: 광주·전남 분리 (2026.05.01 발효) 반영한 권역 매핑
--   2) tennis_org enum + user_tennis_orgs: 한 사용자가 여러 협회에 다른 등급 보유 (multi-org)
--   3) tournaments: 권역·합동 대회·자유 부서명·entry_fee_unit 컬럼
--
-- 배경 보고서:
--   docs/research/tennis-grade-systems.md
--   docs/research/tennis-ecosystem.md
--   docs/superpowers/specs (Phase 2 Spec v2)

-- =========================
-- 1. regions
-- =========================
create table public.regions (
  code text primary key,
  display_name_ko text not null,
  governing_associations text[] not null default '{}',
  uses_kato boolean not null default false,
  uses_kata boolean not null default false,
  notes text,
  created_at timestamptz not null default now()
);

alter table public.regions enable row level security;

create policy regions_authenticated_read on public.regions
  for select using (auth.role() = 'authenticated');

create policy regions_admin_all on public.regions
  for all using (public.is_admin()) with check (public.is_admin());

-- =========================
-- 2. tennis_org enum
-- =========================
create type tennis_org as enum (
  'kta',           -- 대한테니스협회 (통합)
  'kato',          -- 한국테니스발전협의회
  'kata',          -- 한국동호인테니스협회
  'ktfs',          -- 국민생활체육 전국테니스연합회
  'kstf',          -- 한국시니어테니스연맹 (60+)
  'kssta',         -- 한국슈퍼시니어테니스협회
  'kasta',         -- 단식 (단테매)
  'gj',            -- 광주광역시테니스협회 (2026 분리 후 단독)
  'jn',            -- 전라남도테니스협회 (2026 분리 후 단독)
  'local'          -- 시·군 단위 또는 클럽 자체
);

-- =========================
-- 3. user_tennis_orgs (★ Multi-Org 핵심)
-- =========================
create table public.user_tennis_orgs (
  user_id uuid not null references public.users(id) on delete cascade,
  org tennis_org not null,
  division_local text,                                  -- '골드부' / 'KATO 챌린저부' / 자유 텍스트
  score numeric(3,1) check (score is null or (score >= 0 and score <= 10)),
  expires_at date,
  is_primary boolean not null default false,
  region_code text references public.regions(code),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, org)
);

create index user_tennis_orgs_user_idx on public.user_tennis_orgs (user_id);

-- 한 사용자에 primary 협회는 최대 1개
create unique index user_tennis_orgs_one_primary
  on public.user_tennis_orgs (user_id) where is_primary;

create trigger user_tennis_orgs_touch_updated_at
  before update on public.user_tennis_orgs
  for each row execute function public.touch_updated_at();

alter table public.user_tennis_orgs enable row level security;

create policy user_tennis_orgs_self on public.user_tennis_orgs
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy user_tennis_orgs_admin_all on public.user_tennis_orgs
  for all using (public.is_admin()) with check (public.is_admin());

-- =========================
-- 4. tournaments 보강
-- =========================
alter table public.tournaments
  add column region_code text references public.regions(code),
  add column host_associations text[] not null default '{}',
  add column host_orgs tennis_org[] not null default '{}',
  add column division_label_local text,
  add column division_kta_standard text,
  add column entry_fee_unit text not null default 'per_team'
    check (entry_fee_unit in ('per_team', 'per_person')),
  add column is_joint_event boolean not null default false;

create index tournaments_region_idx_v2 on public.tournaments (region_code) where status = 'published';
create index tournaments_host_orgs_gin on public.tournaments using gin (host_orgs) where status = 'published';
