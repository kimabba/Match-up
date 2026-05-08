-- 007_crawl_audit.sql
-- 크롤러 실행 로그

create type crawl_status as enum ('running', 'success', 'partial', 'failed');

create table public.crawl_audit (
  id uuid primary key default gen_random_uuid(),
  source text not null,                 -- 'tennis-gwangju' / 'tennis-jeonnam' / 'tennis-korea'
  status crawl_status not null default 'running',
  fetched_count integer not null default 0,
  inserted_count integer not null default 0,
  updated_count integer not null default 0,
  error text,
  started_at timestamptz not null default now(),
  finished_at timestamptz
);

create index crawl_audit_source_recent_idx on public.crawl_audit (source, started_at desc);

alter table public.crawl_audit enable row level security;

create policy crawl_audit_admin_only on public.crawl_audit
  for all using (public.is_admin()) with check (public.is_admin());
