-- 044: Change tournaments_for_user from RETURNS SETOF tournaments
--      to RETURNS TABLE with explicit columns.
--      Removes embedding (vector 768, ~10KB/row) and embedding_updated_at
--      from search responses. 50-row response: ~500KB → ~20KB savings.
--
-- JY-35: Tech Debt — embedding column in search payload

DROP FUNCTION IF EXISTS public.tournaments_for_user(
  uuid, sport, text, date, date, boolean, text, integer, integer, text, text
);

CREATE OR REPLACE FUNCTION public.tournaments_for_user(
  p_user_id       uuid,
  p_sport         sport    DEFAULT NULL,
  p_region        text     DEFAULT NULL,
  p_date_from     date     DEFAULT NULL,
  p_date_to       date     DEFAULT NULL,
  p_only_my_grade boolean  DEFAULT true,
  p_query         text     DEFAULT NULL,
  p_limit         integer  DEFAULT 50,
  p_offset        integer  DEFAULT 0,
  p_region_code   text     DEFAULT NULL,
  p_host_org      text     DEFAULT NULL
)
RETURNS TABLE (
  id                   uuid,
  sport                sport,
  title                text,
  organizer            text,
  description          text,
  start_date           date,
  end_date             date,
  application_deadline date,
  region               text,
  location             text,
  eligible_grades      text[],
  entry_fee            integer,
  entry_fee_unit       text,
  prize                text,
  format               text,
  source_url           text,
  source               text,
  status               tournament_status,
  submitted_by         uuid,
  approved_by          uuid,
  approved_at          timestamptz,
  rejection_reason     text,
  created_at           timestamptz,
  updated_at           timestamptz,
  region_code          text,
  host_associations    text[],
  host_orgs            tennis_org[],
  division_label_local text,
  division_kta_standard text,
  is_joint_event       boolean,
  player_count         integer,
  division_gender      text,
  division_age_group   text,
  team_count_max       integer,
  team_count_current   integer,
  roster_min           integer,
  roster_max           integer,
  venue_type           text,
  surface_type         text,
  match_format         text,
  host_futsal_orgs     futsal_org[],
  manual_description   boolean
)
LANGUAGE sql STABLE
AS $function$
  with q as (
    select replace(replace(replace(
             coalesce(p_query, ''), '\', '\\'), '%', '\%'), '_', '\_'
           ) as term
  )
  select
    t.id, t.sport, t.title, t.organizer, t.description,
    t.start_date, t.end_date, t.application_deadline,
    t.region, t.location, t.eligible_grades,
    t.entry_fee, t.entry_fee_unit, t.prize, t.format, t.source_url, t.source,
    t.status, t.submitted_by, t.approved_by, t.approved_at, t.rejection_reason,
    t.created_at, t.updated_at,
    t.region_code, t.host_associations, t.host_orgs,
    t.division_label_local, t.division_kta_standard, t.is_joint_event,
    t.player_count, t.division_gender, t.division_age_group,
    t.team_count_max, t.team_count_current, t.roster_min, t.roster_max,
    t.venue_type, t.surface_type, t.match_format,
    t.host_futsal_orgs, t.manual_description
  from public.tournaments t, q
  where t.status = 'published'
    and (p_sport is null or t.sport = p_sport)
    and (p_region is null or t.region = p_region)
    and (p_region_code is null or t.region_code = p_region_code)
    and (p_host_org is null or t.host_orgs @> ARRAY[p_host_org::tennis_org])
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
      or (t.sport = 'tennis' and exists (
        select 1 from public.user_tennis_orgs uto
        where uto.user_id = p_user_id
          and uto.division_codes && t.eligible_grades
      ))
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
