-- 006_notifications.sql
-- FCM 디바이스 토큰 + 발송 이력(중복 방지)

create type device_platform as enum ('ios', 'android', 'web');
create type notification_type as enum ('d_minus_3', 'deadline');
create type notification_status as enum ('pending', 'sent', 'failed');

-- =========================
-- device_tokens
-- =========================
create table public.device_tokens (
  user_id uuid not null references public.users(id) on delete cascade,
  token text not null,
  platform device_platform not null,
  enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);

create index device_tokens_token_idx on public.device_tokens (token) where enabled;

create trigger device_tokens_touch_updated_at
  before update on public.device_tokens
  for each row execute function public.touch_updated_at();

-- =========================
-- notifications_log : 같은 (user, tournament, type) 중복 발송 방지
-- =========================
create table public.notifications_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  type notification_type not null,
  status notification_status not null default 'pending',
  error text,
  sent_at timestamptz,
  created_at timestamptz not null default now()
);

create unique index notifications_log_dedup_idx
  on public.notifications_log (user_id, tournament_id, type);

create index notifications_log_pending_idx
  on public.notifications_log (status, created_at) where status = 'pending';

-- =========================
-- RLS
-- =========================
alter table public.device_tokens enable row level security;
alter table public.notifications_log enable row level security;

create policy device_tokens_self on public.device_tokens
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy device_tokens_admin_read on public.device_tokens
  for select using (public.is_admin());

create policy notifications_log_self_read on public.notifications_log
  for select using (auth.uid() = user_id);

create policy notifications_log_admin_all on public.notifications_log
  for all using (public.is_admin()) with check (public.is_admin());
