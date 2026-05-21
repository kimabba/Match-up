-- 023_review_helpers.sql
-- Phase 3: 검수 큐 통합 view + 일괄 승인/거부 RPC.
--
-- 022 에서 추가된 'rejected' enum 값을 이 마이그레이션부터 참조 가능.

-- =========================
-- view: tournament_review_queue
-- =========================
-- 크롤러 draft + 사용자 제보 draft 를 한 곳에서 조회.
-- submission_kind 로 사용자/크롤러 구분 → 어드민 UI 에서 필터링.
create or replace view public.tournament_review_queue as
select
  t.id,
  t.sport,
  t.title,
  t.organizer,
  t.description,
  t.start_date,
  t.end_date,
  t.application_deadline,
  t.region,
  t.location,
  t.eligible_grades,
  t.entry_fee,
  t.format,
  t.source,
  t.source_url,
  t.submitted_by,
  t.created_at,
  case
    when t.source = 'user_submission' then 'user'
    when t.submitted_by is not null then 'user'
    else 'crawler'
  end as submission_kind,
  u.email as submitted_by_email
from public.tournaments t
left join public.users u on u.id = t.submitted_by
where t.status = 'draft'
  -- ★ 관리자 격리: tournaments RLS 의 user_submit 정책이 본인 draft 조회 허용하므로
  --   view 자체에서 is_admin() 가드 추가. 비관리자가 view 통해 자기 draft 보더라도
  --   어드민 검수 큐 의미만 한정 (UI 단에선 별도 마이 페이지에서 조회).
  and public.is_admin()
order by t.created_at desc;

-- security_invoker = true → tournaments 의 RLS 정책이 호출자 기준으로 평가됨.
-- (admin 권한 가드는 위 WHERE 절의 is_admin() 으로 보장)
alter view public.tournament_review_queue set (security_invoker = true);

-- =========================
-- RPC: tournaments_bulk_approve
-- =========================
-- 입력된 ids 중 status='draft' 인 행만 'published' 로 일괄 승격.
-- 반환값: 실제 update 된 행 수.
create or replace function public.tournaments_bulk_approve(p_ids uuid[])
returns int
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_id uuid := auth.uid();
  affected int;
begin
  if not public.is_admin() then
    raise exception 'admin required';
  end if;
  if p_ids is null or array_length(p_ids, 1) is null then
    return 0;
  end if;

  update public.tournaments
  set
    status = 'published',
    approved_by = caller_id,
    approved_at = now(),
    rejection_reason = null
  where id = any(p_ids)
    and status = 'draft';

  get diagnostics affected = row_count;
  return affected;
end;
$$;

-- =========================
-- RPC: tournaments_bulk_reject
-- =========================
-- 입력된 ids 중 status='draft' 인 행만 'rejected' 로 일괄 거부.
-- 거부 사유 필수. 반환값: 실제 update 된 행 수.
create or replace function public.tournaments_bulk_reject(p_ids uuid[], p_reason text)
returns int
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_id uuid := auth.uid();
  affected int;
begin
  if not public.is_admin() then
    raise exception 'admin required';
  end if;
  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'rejection reason required';
  end if;
  if p_ids is null or array_length(p_ids, 1) is null then
    return 0;
  end if;

  update public.tournaments
  set
    status = 'rejected',
    approved_by = caller_id,
    approved_at = now(),
    rejection_reason = p_reason
  where id = any(p_ids)
    and status = 'draft';

  get diagnostics affected = row_count;
  return affected;
end;
$$;

revoke all on function public.tournaments_bulk_approve(uuid[]) from public;
revoke all on function public.tournaments_bulk_reject(uuid[], text) from public;
grant execute on function public.tournaments_bulk_approve(uuid[]) to authenticated;
grant execute on function public.tournaments_bulk_reject(uuid[], text) to authenticated;
