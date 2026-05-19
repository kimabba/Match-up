-- rate limit table for chat and semantic-search (10 requests/minute per user)
create table public.chat_rate_limit (
  user_id uuid primary key references public.users(id) on delete cascade,
  window_start timestamptz not null default now(),
  count int not null default 0
);

-- Only the user themselves can read their own rate limit row (not needed by app directly)
alter table public.chat_rate_limit enable row level security;
-- Service role can do everything (Edge Functions use service role client)
-- No user-facing RLS needed since Edge Functions bypass RLS with service_role
