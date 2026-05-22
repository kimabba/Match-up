-- 027_db_crawler_review_fixes.sql
-- DB 설계 구조 및 크롤링 시스템 점검 결과 반영 (1단계 및 2단계 일부)
--
-- 변경 사항:
--   1) crawl_sources.id 기본값을 uuid_generate_v7() 에서 gen_random_uuid() (v4)로 변경
--      (이유: uuid_generate_v7()의 service_role 권한 한정으로 인해 authenticated 관리자의 소스 등록이 차단되던 문제 해결)
--   2) prevent_role_self_update() 트리거 함수에 auth.uid() is not null 예외 추가
--      (이유: 최초 관리자가 없는 상태에서 SQL Editor 또는 service_role 로 관리자 임명이 불가능한 부트스트랩 문제 해결)
--   3) 만료된 대회를 자동으로 'closed' 상태로 변경하는 cron 및 RPC 추가
--      (이유: 기간이 만료된 대회가 계속 published 상태로 유지되어 생기는 벡터 인덱스 비대화 및 검색 노이즈 방지)

-- 1) crawl_sources.id 기본값 변경
alter table public.crawl_sources
  alter column id set default gen_random_uuid();

-- 2) prevent_role_self_update 트리거 함수 개선 (auth.uid()가 null 이 아닌 경우에만 차단)
create or replace function public.prevent_role_self_update()
returns trigger language plpgsql as $$
begin
  if old.role is distinct from new.role and auth.uid() is not null and not public.is_admin() then
    raise exception 'role 컬럼은 관리자만 변경할 수 있습니다';
  end if;
  return new;
end;
$$;

-- 3) 만료된 대회의 closed 상태 자동 전환 RPC 추가
create or replace function public.close_expired_tournaments()
returns int
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  affected int;
begin
  update public.tournaments
  set status = 'closed'
  where status = 'published'
    and (
      end_date < now()::date
      or (end_date is null and start_date < now()::date)
    );

  get diagnostics affected = row_count;
  return affected;
end;
$$;

comment on function public.close_expired_tournaments() is
  'published 상태인 대회 중 날짜가 만료된 대회를 closed 상태로 자동 마감 처리합니다.';

-- 권한 제어: 비공개 실행 허용
revoke all on function public.close_expired_tournaments() from public;
grant execute on function public.close_expired_tournaments() to service_role, postgres;

-- 4) 매일 새벽 3시(UTC 18:00 = KST 03:00)에 마감 업데이트하는 pg_cron 등록
do $$
declare
  rec record;
begin
  for rec in select jobid from cron.job where jobname = 'close-expired-tournaments-daily'
  loop
    perform cron.unschedule(rec.jobid);
  end loop;
end $$;

select cron.schedule(
  'close-expired-tournaments-daily',
  '0 18 * * *', -- UTC 18:00 = KST 03:00
  $$ select public.close_expired_tournaments(); $$
);
