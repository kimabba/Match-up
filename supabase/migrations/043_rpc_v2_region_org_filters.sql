-- 043: Add p_region_code + p_host_org to tournaments_for_user,
--      fix tournaments_semantic_search to use division_codes for tennis.
--
-- Background (JY-44):
--   - tournaments-search Edge Function does client-side filtering for
--     region_code and host_org because the RPC lacked those params.
--   - This breaks pagination (limit/offset applied before filter).
--   - tournaments_semantic_search still uses user_sports.grade for tennis
--     matching, which never matches division codes like gj_m_gold.
--     041 fixed tournaments_for_user but not the semantic search.

-- 1) Update tournaments_for_user — add p_region_code, p_host_org
--    Must drop old signature first; new default params make it a different overload.
DROP FUNCTION IF EXISTS public.tournaments_for_user(uuid, sport, text, date, date, boolean, text, integer, integer);

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


-- 2) Update tournaments_semantic_search — fix tennis grade matching
--    Old: user_sports.grade = any(eligible_grades) → never matches division codes
--    New: same 3-branch logic as tournaments_for_user (041)

drop function if exists public.tournaments_semantic_search(uuid, vector, boolean, int, text);

create or replace function public.tournaments_semantic_search(
  p_user_id uuid,
  p_query_embedding vector(768),
  p_only_my_grade boolean default true,
  p_match_count int default 10,
  p_sport text default null
)
returns table (
  id uuid,
  sport sport,
  title text,
  start_date date,
  region text,
  eligible_grades text[],
  similarity real
)
language sql
stable
security invoker
as $$
  select
    t.id,
    t.sport,
    t.title,
    t.start_date,
    t.region,
    t.eligible_grades,
    (1 - (t.embedding <=> p_query_embedding))::real as similarity
  from public.tournaments t
  where t.status = 'published'
    and t.embedding is not null
    and (p_sport is null or t.sport::text = p_sport)
    and (
      not p_only_my_grade
      -- Tennis: division_codes matching (same as tournaments_for_user)
      or (t.sport = 'tennis' and exists (
        select 1 from public.user_tennis_orgs uto
        where uto.user_id = p_user_id
          and uto.division_codes && t.eligible_grades
      ))
      -- Tennis fallback: no org registered → show all
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
      -- Non-tennis: original grade matching
      or (t.sport != 'tennis' and exists (
        select 1 from public.user_sports us
        where us.user_id = p_user_id
          and us.sport = t.sport
          and us.grade = any(t.eligible_grades)
      ))
    )
  order by t.embedding <=> p_query_embedding
  limit greatest(p_match_count, 1);
$$;

grant execute on function public.tournaments_semantic_search(uuid, vector, boolean, int, text) to authenticated;
