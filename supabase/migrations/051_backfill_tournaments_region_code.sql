-- 051_backfill_tournaments_region_code.sql
--
-- 배경: 크롤러(crawler.ts)가 대회 저장 시 region(한글)만 넣고 region_code 를
--   설정하지 않아, published 대회 대부분이 region_code=null 상태였다.
--   → RPC v2(044)의 서버사이드 지역 필터(p_region_code)가 무력화됨.
--   또한 일부 행은 region='광주' 인데 region_code='jeonnam' 으로 오매칭돼 있었다.
--
-- 조치: regions.display_name_ko 를 기준(source of truth)으로 region_code 를 재설정.
--   한글명이 정확히 일치하는 행만 채우고, 오매칭 행도 region 기준으로 교정한다.
--   (코드 측 재발 방지는 crawler.ts 의 regionCodeFromLabel 적용으로 처리됨)

update public.tournaments t
set region_code = r.code
from public.regions r
where t.region = r.display_name_ko
  and t.region_code is distinct from r.code;
