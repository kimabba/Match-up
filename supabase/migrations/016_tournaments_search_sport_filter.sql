-- 016_tournaments_search_sport_filter.sql
-- tournaments_semantic_search 에 p_sport 파라미터 추가.
--
-- 배경:
--   - 사용자가 메시지에 종목 키워드 (테니스/풋살) 를 명시했을 때,
--     RAG top-k 가 종목 무관하게 뽑힌 뒤 JS 단에서 post-filter 하면
--     요청 종목 행이 top-k 밖으로 밀려나 false RAG-miss 가 발생.
--   - 해결: DB 단에서 p_sport 로 사전 필터링한 뒤 top-k 산출.
--
-- 호환성:
--   - rules_semantic_search (005) 는 이미 p_sport 파라미터를 가짐 (sport enum).
--   - 본 RPC 는 인자 추가 → PostgreSQL 입장에서 새 오버로드로 인식.
--     기존 시그니처 (uuid, vector, boolean, int) 를 명시적으로 drop 한 뒤 새로 create.
--   - 기존 호출자가 p_sport 를 빠뜨려도 default null 이므로 동작은 동일.
--   - p_sport 타입은 text 로 받아 내부에서 t.sport::text 와 비교 → JS string 직접 전달 가능.

drop function if exists public.tournaments_semantic_search(uuid, vector, boolean, int);

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
      or exists (
        select 1 from public.user_sports us
        where us.user_id = p_user_id
          and us.sport = t.sport
          and us.grade = any(t.eligible_grades)
      )
    )
  order by t.embedding <=> p_query_embedding
  limit greatest(p_match_count, 1);
$$;

grant execute on function public.tournaments_semantic_search(uuid, vector, boolean, int, text) to authenticated;
