-- 008_cron.sql
-- pg_cron 스케줄: 크롤러, 알림, 임베딩 워커
--
-- pg_net.http_post 으로 Edge Function 을 트리거한다.
-- 실 운영에서는 SUPABASE_URL, SERVICE_ROLE_KEY 를 vault 또는 GUC 로 주입.
-- 로컬에서는 supabase secrets set CRON_INVOKE_URL=... CRON_INVOKE_KEY=... 후
-- 아래 GUC 로 노출하거나 배포 시 한 번만 alter system set 으로 주입.
--
-- ⚠️ 배포 시 아래 두 GUC 가 설정되어 있어야 한다.
--    alter database postgres set app.cron_invoke_url = 'https://<project>.functions.supabase.co';
--    alter database postgres set app.cron_invoke_key = '<service-role-jwt>';

create or replace function public.invoke_edge_function(fn_name text, body jsonb default '{}'::jsonb)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  invoke_url text := current_setting('app.cron_invoke_url', true);
  invoke_key text := current_setting('app.cron_invoke_key', true);
  request_id bigint;
begin
  if invoke_url is null or invoke_key is null then
    raise notice 'cron invoke url/key not configured; skipping %', fn_name;
    return null;
  end if;

  select net.http_post(
    url := invoke_url || '/' || fn_name,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || invoke_key
    ),
    body := body
  ) into request_id;

  return request_id;
end;
$$;

-- 1) 임베딩 워커: 5분 간격
select cron.schedule(
  'embed-pending-every-5min',
  '*/5 * * * *',
  $$ select public.invoke_edge_function('embed-pending'); $$
);

-- 2) 알림 워커: 매시 정각
select cron.schedule(
  'notify-cron-hourly',
  '0 * * * *',
  $$ select public.invoke_edge_function('notify-cron'); $$
);

-- 3) 테니스 크롤러: 매일 오전 6시 (KST 기준은 운영 시 조정)
select cron.schedule(
  'crawl-tennis-gwangju-daily',
  '0 21 * * *',  -- UTC 21:00 = KST 06:00
  $$ select public.invoke_edge_function('crawl-tennis-gwangju'); $$
);

select cron.schedule(
  'crawl-tennis-jeonnam-daily',
  '15 21 * * *',
  $$ select public.invoke_edge_function('crawl-tennis-jeonnam'); $$
);

select cron.schedule(
  'crawl-tennis-korea-daily',
  '30 21 * * *',
  $$ select public.invoke_edge_function('crawl-tennis-korea'); $$
);
