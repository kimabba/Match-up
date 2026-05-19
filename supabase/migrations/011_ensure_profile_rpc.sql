-- 011_ensure_profile_rpc.sql
-- 로그인한 사용자의 public.users 행이 없으면 자동 생성하는 RPC.
-- 앱이 user_sports insert 전에 호출해 FK 오류를 방지한다.

create or replace function public.ensure_profile()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (id, email)
  select auth.uid(), email
  from auth.users
  where id = auth.uid()
  on conflict (id) do nothing;
end;
$$;

-- 모든 인증 사용자가 호출 가능
grant execute on function public.ensure_profile() to authenticated;
