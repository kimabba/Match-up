-- 075: tournaments_for_user 에 부서/등급 필터(p_division_codes) 추가
--
-- 배경:
--   상세검색에서 특정 부서(오픈부/골드부/신인부 …)로 거를 수 있게 한다.
--   eligible_grades 는 종목별 코드 배열(테니스 {org}_{suffix}, 풋살 grade)이라,
--   프론트가 선택한 부서를 협회 무관 코드 집합으로 펼쳐 보내면
--   배열 겹침(&&)으로 거른다. 기존 등급 매칭과 동일 연산이라 안전하고,
--   테니스/풋살 모두 같은 방식으로 동작한다.
--
-- 변경:
--   tournaments_for_user 에 p_division_codes text[] 파라미터 추가(맨 끝, 기본 NULL).
--   WHERE: (p_division_codes IS NULL OR p_division_codes && t.eligible_grades)
--   그 외 시그니처/로직은 072 와 동일.

-- 072 의 11-파라미터 버전 제거.
DROP FUNCTION IF EXISTS public.tournaments_for_user(uuid, text, text, date, date, boolean, text, integer, integer, text, text);

CREATE FUNCTION public.tournaments_for_user(
  p_user_id uuid,
  p_sport text DEFAULT NULL,
  p_region text DEFAULT NULL,
  p_date_from date DEFAULT NULL,
  p_date_to date DEFAULT NULL,
  p_only_my_grade boolean DEFAULT true,
  p_query text DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0,
  p_region_code text DEFAULT NULL,
  p_host_org text DEFAULT NULL,
  p_division_codes text[] DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  sport text,
  title text,
  organizer text,
  description text,
  start_date date,
  end_date date,
  application_deadline date,
  region text,
  region_code text,
  host_associations text[],
  location text,
  eligible_grades text[],
  division_label_local text,
  entry_fee integer,
  entry_fee_unit text,
  prize text,
  format text,
  source_url text,
  status text,
  created_at timestamptz,
  host_orgs public.tennis_org[],
  division_kta_standard text,
  division_gender text,
  division_age_group text,
  is_joint_event boolean,
  host_futsal_orgs public.futsal_org[],
  t_venue_type text,
  t_surface_type text,
  t_match_format text,
  t_player_count integer,
  t_team_count_max integer,
  t_roster_min integer,
  t_roster_max integer,
  futsal_event_category text
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT
    t.id,
    t.sport::text,
    t.title,
    t.organizer,
    t.description,
    t.start_date,
    t.end_date,
    t.application_deadline,
    t.region,
    t.region_code,
    t.host_associations,
    t.location,
    t.eligible_grades,
    t.division_label_local,
    t.entry_fee,
    t.entry_fee_unit,
    t.prize,
    t.format,
    t.source_url,
    t.status::text,
    t.created_at,
    tt.host_orgs,
    tt.division_kta_standard,
    tt.division_gender,
    tt.division_age_group,
    tt.is_joint_event,
    ft.host_futsal_orgs,
    ft.venue_type,
    ft.surface_type,
    ft.match_format,
    ft.player_count,
    ft.team_count_max,
    ft.roster_min,
    ft.roster_max,
    ft.event_category
  FROM public.tournaments t
  LEFT JOIN public.tennis_tournament_details tt
    ON tt.tournament_id = t.id
  LEFT JOIN public.futsal_tournament_details ft
    ON ft.tournament_id = t.id
  WHERE t.status = 'published'
    AND (p_sport IS NULL OR t.sport::text = p_sport)
    AND (p_region IS NULL OR t.region = p_region)
    AND (p_region_code IS NULL OR t.region_code = p_region_code)
    AND (p_date_from IS NULL OR t.start_date >= p_date_from)
    AND (p_date_to IS NULL OR t.start_date <= p_date_to)
    AND (
      p_host_org IS NULL
      OR tt.host_orgs @> ARRAY[p_host_org::public.tennis_org]
    )
    -- 부서/등급 필터: 선택한 부서 코드 집합과 eligible_grades 가 겹치면 통과.
    AND (p_division_codes IS NULL OR p_division_codes && t.eligible_grades)
    AND (
      p_query IS NULL
      OR t.title ILIKE '%' || p_query || '%'
      OR COALESCE(t.organizer, '') ILIKE '%' || p_query || '%'
      OR COALESCE(t.description, '') ILIKE '%' || p_query || '%'
    )
    AND (
      NOT p_only_my_grade
      OR (
        -- 테니스: user_tennis_orgs.division_codes 기반 (광주/전남 교차 포함)
        (t.sport = 'tennis' AND EXISTS (
          SELECT 1 FROM public.user_tennis_orgs uto
          WHERE uto.user_id = p_user_id
            AND public.expand_gj_jn_codes(uto.division_codes) && t.eligible_grades
        ))
        OR
        -- 풋살: 기존 user_sports.grade 기반
        (t.sport = 'futsal' AND EXISTS (
          SELECT 1 FROM public.user_sports us
          WHERE us.user_id = p_user_id
            AND us.sport = t.sport
            AND us.grade = ANY(t.eligible_grades)
        ))
      )
    )
  ORDER BY t.start_date ASC, t.created_at DESC
  LIMIT GREATEST(p_limit, 0)
  OFFSET GREATEST(p_offset, 0);
$$;
