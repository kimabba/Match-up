-- 002_init_users_sports.sql
-- 사용자 + 종목·등급 다중 등록 + RLS

-- =========================
-- enum
-- =========================
create type sport as enum ('tennis', 'futsal');
create type user_role as enum ('user', 'admin');

-- 등급은 종목별로 다르므로 text + check constraint 로 표현
-- tennis: rookie, div5, div4, div3, div2, div1 (낮은 부수가 상위)
-- futsal: beginner, intermediate, advanced

-- =========================
-- users (auth.users 의 메타데이터 미러)
-- =========================
create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  display_name text,
  role user_role not null default 'user',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index users_email_idx on public.users (lower(email));

-- 가입 시 자동으로 public.users row 생성
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (id, email, display_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- updated_at 자동 갱신
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger users_touch_updated_at
  before update on public.users
  for each row execute function public.touch_updated_at();

-- =========================
-- 관리자 판별 helper (RLS 재귀 회피용 SECURITY DEFINER)
-- =========================
create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.users where id = auth.uid() and role = 'admin'
  );
$$;

-- 일반 사용자가 자신의 role 을 변경하지 못하도록 차단
create or replace function public.prevent_role_self_update()
returns trigger language plpgsql as $$
begin
  if old.role is distinct from new.role and not public.is_admin() then
    raise exception 'role 컬럼은 관리자만 변경할 수 있습니다';
  end if;
  return new;
end;
$$;

create trigger users_prevent_role_self_update
  before update on public.users
  for each row execute function public.prevent_role_self_update();

-- =========================
-- user_sports : 한 사용자가 N개 종목 등록
-- =========================
create table public.user_sports (
  user_id uuid not null references public.users(id) on delete cascade,
  sport sport not null,
  grade text not null,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (user_id, sport),
  constraint user_sports_grade_check check (
    (sport = 'tennis' and grade in ('rookie', 'div5', 'div4', 'div3', 'div2', 'div1'))
    or
    (sport = 'futsal' and grade in ('beginner', 'intermediate', 'advanced'))
  )
);

create index user_sports_user_idx on public.user_sports (user_id);

-- 한 사용자에 primary 종목은 최대 1개
create unique index user_sports_one_primary_per_user
  on public.user_sports (user_id) where is_primary;

-- =========================
-- RLS
-- =========================
alter table public.users enable row level security;
alter table public.user_sports enable row level security;

-- users: 본인 row 조회/수정 + 관리자 전체
create policy users_self_read on public.users
  for select using (auth.uid() = id);

create policy users_self_update on public.users
  for update using (auth.uid() = id) with check (auth.uid() = id);

create policy users_admin_all on public.users
  for all using (public.is_admin()) with check (public.is_admin());

-- user_sports: 본인 + 관리자
create policy user_sports_self_read on public.user_sports
  for select using (auth.uid() = user_id);

create policy user_sports_self_write on public.user_sports
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy user_sports_admin_all on public.user_sports
  for all using (public.is_admin()) with check (public.is_admin());
