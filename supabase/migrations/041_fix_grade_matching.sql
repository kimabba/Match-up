-- 041: Fix grade matching — user_tennis_orgs.division_codes + RPC update
-- Problem: tournaments_for_user compared user_sports.grade (경력 텍스트)
--          with tournaments.eligible_grades (부서코드) → never matched.
-- Fix: Add division_codes[] to user_tennis_orgs, use it in RPC for tennis.

-- 1) Add division_codes column
ALTER TABLE public.user_tennis_orgs
  ADD COLUMN IF NOT EXISTS division_codes text[] NOT NULL DEFAULT '{}';

COMMENT ON COLUMN public.user_tennis_orgs.division_codes IS
  'Selected division codes from tennisDivisions (e.g. gj_m_gold). Used by tournaments_for_user RPC.';

-- 2) Replace tournaments_for_user RPC
CREATE OR REPLACE FUNCTION public.tournaments_for_user(
  p_user_id   uuid,
  p_sport     sport    DEFAULT NULL,
  p_region    text     DEFAULT NULL,
  p_date_from date     DEFAULT NULL,
  p_date_to   date     DEFAULT NULL,
  p_only_my_grade boolean DEFAULT true,
  p_query     text     DEFAULT NULL,
  p_limit     integer  DEFAULT 50,
  p_offset    integer  DEFAULT 0
)
RETURNS SETOF tournaments
LANGUAGE sql STABLE
AS $function$
  with q as (
    select replace(replace(replace(
             coalesce(p_query, ''), '\', '\\'), '%', '\%'), '_', '\_'
           ) as term
  )
  select t.*
  from public.tournaments t, q
  where t.status = 'published'
    and (p_sport is null or t.sport = p_sport)
    and (p_region is null or t.region = p_region)
    and (p_date_from is null or t.start_date >= p_date_from)
    and (p_date_to is null or t.start_date <= p_date_to)
    and (
      p_query is null
      or t.title ilike '%' || q.term || '%' escape '\'
      or coalesce(t.organizer, '') ilike '%' || q.term || '%' escape '\'
      or coalesce(t.description, '') ilike '%' || q.term || '%' escape '\'
    )
    and (
      not p_only_my_grade
      -- Tennis: match user_tennis_orgs.division_codes against eligible_grades
      or (t.sport = 'tennis' and exists (
        select 1 from public.user_tennis_orgs uto
        where uto.user_id = p_user_id
          and uto.division_codes && t.eligible_grades
      ))
      -- Tennis fallback: user registered tennis but no org → show all tennis
      or (t.sport = 'tennis'
        and exists (
          select 1 from public.user_sports us
          where us.user_id = p_user_id and us.sport = 'tennis'
        )
        and not exists (
          select 1 from public.user_tennis_orgs uto
          where uto.user_id = p_user_id
        )
      )
      -- Non-tennis (futsal etc): keep original grade matching
      or (t.sport != 'tennis' and exists (
        select 1 from public.user_sports us
        where us.user_id = p_user_id
          and us.sport = t.sport
          and us.grade = any(t.eligible_grades)
      ))
    )
  order by t.start_date asc, t.created_at desc
  limit greatest(p_limit, 0)
  offset greatest(p_offset, 0);
$function$;
