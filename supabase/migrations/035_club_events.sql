-- 035_club_events.sql
-- 클럽 활동 MVP: 모임 일정(club_events) + 참석(club_event_attendees)
--
-- 권한 모델:
--   - 조회: 클럽 active 멤버
--   - 생성: active 멤버 누구나. 단 type='official'은 운영진(owner/manager)만, 'casual'은 모두
--   - 수정/삭제: 작성자 또는 운영진(또는 전역 admin)
--   - 참석: 본인 응답 upsert (해당 클럽 멤버만)
-- 멤버십 평가는 기존 security definer 헬퍼(is_active_club_member / is_club_manager)로 재귀 회피.

-- 클라이언트(authenticated)가 직접 INSERT 시 default uuid_generate_v7() 를 호출하므로 execute 권한 부여
grant execute on function public.uuid_generate_v7() to authenticated;

create table if not exists public.club_events (
  id            uuid primary key default public.uuid_generate_v7(),
  club_id       uuid not null references public.clubs(id) on delete cascade,
  created_by    uuid not null references auth.users(id),
  type          text not null default 'casual' check (type in ('official', 'casual')),
  title         text not null check (length(title) between 1 and 100),
  description   text,
  location_text text,
  starts_at     timestamptz not null,
  created_at    timestamptz not null default now()
);
create index if not exists club_events_club_starts_idx
  on public.club_events (club_id, starts_at);

create table if not exists public.club_event_attendees (
  id           uuid primary key default public.uuid_generate_v7(),
  event_id     uuid not null references public.club_events(id) on delete cascade,
  user_id      uuid not null references auth.users(id),
  status       text not null check (status in ('going', 'not_going')),
  responded_at timestamptz not null default now(),
  unique (event_id, user_id)
);
create index if not exists club_event_attendees_event_idx
  on public.club_event_attendees (event_id);

-- 이벤트 id 로 해당 클럽 active 멤버 여부 평가 (attendees RLS 용)
create or replace function public.is_event_club_member(p_event_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.club_events e
    join public.club_members m on m.club_id = e.club_id
    where e.id = p_event_id
      and m.user_id = auth.uid()
      and m.status = 'active'
  );
$$;

-- 이벤트 id 로 운영진 여부 (작성자 외 운영진 수정/삭제 판단에 사용 가능)
create or replace function public.is_event_club_manager(p_event_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.club_events e
    join public.club_members m on m.club_id = e.club_id
    where e.id = p_event_id
      and m.user_id = auth.uid()
      and m.role in ('owner', 'manager')
      and m.status = 'active'
  );
$$;

-- ── RLS: club_events ──────────────────────────────────────────
alter table public.club_events enable row level security;

drop policy if exists club_events_select on public.club_events;
create policy club_events_select on public.club_events
  for select using (
    public.is_admin()
    or public.is_active_club_member(club_id)
  );

drop policy if exists club_events_insert on public.club_events;
create policy club_events_insert on public.club_events
  for insert with check (
    created_by = auth.uid()
    and public.is_active_club_member(club_id)
    and (type = 'casual' or public.is_club_manager(club_id))
  );

drop policy if exists club_events_update on public.club_events;
create policy club_events_update on public.club_events
  for update using (
    public.is_admin()
    or created_by = auth.uid()
    or public.is_club_manager(club_id)
  ) with check (
    -- 공식으로 승격은 운영진만
    type = 'casual' or public.is_club_manager(club_id) or public.is_admin()
  );

drop policy if exists club_events_delete on public.club_events;
create policy club_events_delete on public.club_events
  for delete using (
    public.is_admin()
    or created_by = auth.uid()
    or public.is_club_manager(club_id)
  );

-- ── RLS: club_event_attendees ─────────────────────────────────
alter table public.club_event_attendees enable row level security;

drop policy if exists club_event_attendees_select on public.club_event_attendees;
create policy club_event_attendees_select on public.club_event_attendees
  for select using (
    public.is_admin()
    or public.is_event_club_member(event_id)
  );

drop policy if exists club_event_attendees_insert on public.club_event_attendees;
create policy club_event_attendees_insert on public.club_event_attendees
  for insert with check (
    user_id = auth.uid()
    and public.is_event_club_member(event_id)
  );

drop policy if exists club_event_attendees_update on public.club_event_attendees;
create policy club_event_attendees_update on public.club_event_attendees
  for update using (
    user_id = auth.uid()
    and public.is_event_club_member(event_id)
  );

drop policy if exists club_event_attendees_delete on public.club_event_attendees;
create policy club_event_attendees_delete on public.club_event_attendees
  for delete using (user_id = auth.uid());
