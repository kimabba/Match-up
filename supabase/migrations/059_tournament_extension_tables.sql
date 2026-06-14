-- 059: tournaments 공통+확장 분리
--
-- 1. tennis_tournament_details 생성 + 데이터 이관
-- 2. futsal_tournament_details 생성 + 데이터 이관
-- 3. tournaments에서 종목별 컬럼 제거
-- 4. tournaments_for_user RPC 재정의 (JOIN 추가)
-- 5. tournaments_semantic_search RPC 재정의

BEGIN;

-- ═══════════════════════════════════════════════════════════════
-- 1. tennis_tournament_details
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.tennis_tournament_details (
  tournament_id uuid PRIMARY KEY REFERENCES public.tournaments(id) ON DELETE CASCADE,
  host_orgs tennis_org[] NOT NULL DEFAULT '{}',
  division_kta_standard text,
  division_gender text,
  division_age_group text,
  is_joint_event boolean NOT NULL DEFAULT false
);

ALTER TABLE public.tennis_tournament_details ENABLE ROW LEVEL SECURITY;

CREATE POLICY tennis_details_read ON public.tennis_tournament_details
  FOR SELECT USING (true);

CREATE POLICY tennis_details_admin ON public.tennis_tournament_details
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- 기존 데이터 이관
INSERT INTO public.tennis_tournament_details
  (tournament_id, host_orgs, division_kta_standard, division_gender, division_age_group, is_joint_event)
SELECT id, host_orgs, division_kta_standard, division_gender, division_age_group, is_joint_event
FROM public.tournaments
WHERE sport = 'tennis';

-- ═══════════════════════════════════════════════════════════════
-- 2. futsal_tournament_details
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.futsal_tournament_details (
  tournament_id uuid PRIMARY KEY REFERENCES public.tournaments(id) ON DELETE CASCADE,
  host_futsal_orgs futsal_org[] NOT NULL DEFAULT '{}',
  venue_type text,
  surface_type text,
  match_format text,
  player_count int,
  team_count_max int,
  roster_min int,
  roster_max int
);

ALTER TABLE public.futsal_tournament_details ENABLE ROW LEVEL SECURITY;

CREATE POLICY futsal_details_read ON public.futsal_tournament_details
  FOR SELECT USING (true);

CREATE POLICY futsal_details_admin ON public.futsal_tournament_details
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- 기존 데이터 이관
INSERT INTO public.futsal_tournament_details
  (tournament_id, host_futsal_orgs, venue_type, surface_type, match_format, player_count, team_count_max, roster_min, roster_max)
SELECT id, host_futsal_orgs, venue_type, surface_type, match_format, player_count, team_count_max, roster_min, roster_max
FROM public.tournaments
WHERE sport = 'futsal';

-- ═══════════════════════════════════════════════════════════════
-- 3. tournaments에서 종목별 컬럼 제거
-- ═══════════════════════════════════════════════════════════════

-- 인덱스 먼저 제거
DROP INDEX IF EXISTS tournaments_host_orgs_gin;

ALTER TABLE public.tournaments
  DROP COLUMN IF EXISTS host_orgs,
  DROP COLUMN IF EXISTS division_kta_standard,
  DROP COLUMN IF EXISTS division_gender,
  DROP COLUMN IF EXISTS division_age_group,
  DROP COLUMN IF EXISTS is_joint_event,
  DROP COLUMN IF EXISTS host_futsal_orgs,
  DROP COLUMN IF EXISTS venue_type,
  DROP COLUMN IF EXISTS surface_type,
  DROP COLUMN IF EXISTS match_format,
  DROP COLUMN IF EXISTS player_count,
  DROP COLUMN IF EXISTS team_count_max,
  DROP COLUMN IF EXISTS team_count_current,
  DROP COLUMN IF EXISTS roster_min,
  DROP COLUMN IF EXISTS roster_max;

-- ═══════════════════════════════════════════════════════════════
-- 4. tournaments_for_user RPC 재정의 (확장 테이블 JOIN)
-- ═══════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.tournaments_for_user(uuid, text, text, int, int);

CREATE OR REPLACE FUNCTION public.tournaments_for_user(
  p_user_id uuid,
  p_region_code text DEFAULT NULL,
  p_host_org text DEFAULT NULL,
  p_limit int DEFAULT 50,
  p_offset int DEFAULT 0
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
  location text,
  eligible_grades text[],
  division_label_local text,
  entry_fee int,
  entry_fee_unit text,
  prize text,
  format text,
  source_url text,
  status text,
  created_at timestamptz,
  -- 테니스 확장
  host_orgs tennis_org[],
  division_kta_standard text,
  division_gender text,
  division_age_group text,
  is_joint_event boolean,
  -- 풋살 확장
  host_futsal_orgs futsal_org[],
  t_venue_type text,
  t_surface_type text,
  t_match_format text,
  t_player_count int,
  t_team_count_max int,
  t_roster_min int,
  t_roster_max int
)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = public
AS $$
  SELECT
    t.id, t.sport::text, t.title, t.organizer, t.description,
    t.start_date, t.end_date, t.application_deadline,
    t.region, t.region_code, t.location,
    t.eligible_grades, t.division_label_local,
    t.entry_fee, t.entry_fee_unit, t.prize, t.format,
    t.source_url, t.status::text, t.created_at,
    -- 테니스 (LEFT JOIN이라 풋살이면 모두 NULL)
    tt.host_orgs,
    tt.division_kta_standard,
    tt.division_gender,
    tt.division_age_group,
    tt.is_joint_event,
    -- 풋살
    ft.host_futsal_orgs,
    ft.venue_type,
    ft.surface_type,
    ft.match_format,
    ft.player_count,
    ft.team_count_max,
    ft.roster_min,
    ft.roster_max
  FROM public.tournaments t
  LEFT JOIN public.tennis_tournament_details tt ON tt.tournament_id = t.id
  LEFT JOIN public.futsal_tournament_details ft ON ft.tournament_id = t.id
  WHERE t.status = 'published'
    AND (p_region_code IS NULL OR t.region_code = p_region_code)
    AND (p_host_org IS NULL OR tt.host_orgs @> ARRAY[p_host_org::tennis_org])
  ORDER BY t.start_date ASC
  LIMIT p_limit OFFSET p_offset;
$$;

-- ═══════════════════════════════════════════════════════════════
-- 5. tournaments_semantic_search RPC 재정의
-- ═══════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.tournaments_semantic_search(uuid, vector, boolean, text, int);

CREATE OR REPLACE FUNCTION public.tournaments_semantic_search(
  p_user_id uuid,
  p_query_embedding vector(768),
  p_only_my_grade boolean DEFAULT false,
  p_sport text DEFAULT NULL,
  p_match_count int DEFAULT 5
)
RETURNS TABLE (
  id uuid,
  sport text,
  title text,
  start_date date,
  region text,
  eligible_grades text[],
  similarity float
)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = public
AS $$
  SELECT
    t.id, t.sport::text, t.title, t.start_date,
    t.region, t.eligible_grades,
    1 - (t.embedding <=> p_query_embedding) AS similarity
  FROM public.tournaments t
  WHERE t.status = 'published'
    AND t.embedding IS NOT NULL
    AND (p_sport IS NULL OR t.sport::text = p_sport)
  ORDER BY t.embedding <=> p_query_embedding
  LIMIT p_match_count;
$$;

COMMIT;
