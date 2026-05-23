-- 028_adjust_crawler_schedule.sql
--
-- 크롤러 스케줄 조정: KST 22:00 ~ 06:00 (밤 10시 ~ 새벽 6시) 사이에는 크롤링을 수행하지 않고,
-- 활성 시간대(06:00 ~ 22:00 KST)에는 30분 간격으로 실행합니다.
--
-- KST 06:00 ~ 22:00 = UTC 21:00 ~ 13:00
-- 22:30 KST 실행을 방지하기 위해 정규 스케줄(매시 0분, 30분)은 UTC 12:30(KST 21:30)까지만 돌리고,
-- 마지막 KST 22:00(UTC 13:00)은 정각 1회만 단독 실행하도록 나눕니다.

do $$
declare
  rec record;
begin
  for rec in select jobid from cron.job where jobname in ('crawl-dispatch', 'crawl-dispatch-regular', 'crawl-dispatch-last')
  loop
    perform cron.unschedule(rec.jobid);
  end loop;
end $$;

-- 1) KST 06:00 ~ 21:30 (UTC 21:00 ~ 12:30) 매 30분 실행
select cron.schedule(
  'crawl-dispatch-regular',
  '0,30 0-12,21-23 * * *',
  $$ select public.invoke_edge_function('crawl-dispatch'); $$
);

-- 2) KST 22:00 (UTC 13:00) 실행
select cron.schedule(
  'crawl-dispatch-last',
  '0 13 * * *',
  $$ select public.invoke_edge_function('crawl-dispatch'); $$
);
