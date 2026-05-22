-- 026_futsal_crawl_sources.sql
-- 풋살 대회 크롤 소스 등록
--
-- 리서치 기준 (2026-05-22):
--   크롤 우선순위: 한국풋살연맹 > 스포위크 > 경기도풋살연합회 > S리그 > 위밋업
--   모두 비로그인 열람 가능한 정적/PHP 게시판 구조
--
-- 초기 등록 시 enabled = false (URL 구조·파서 검증 후 활성화)
-- 파서 모듈 키는 dispatcher Edge Function 매핑에 사용

insert into public.crawl_sources
  (name, slug, url, sport, region, source_type, parser_module, schedule_cron, enabled, notes)
values
  (
    '한국풋살연맹 대회공지',
    'futsal-kfl',
    'http://www.futsal.or.kr/',
    'futsal',
    null,
    'board',
    'futsal-kfl-board',
    '0 20 * * *',
    false,
    '한국풋살연맹 공식 사이트. PHP 게시판. URL·파서 검증 후 활성화 필요. 전국 대회 중심.'
  ),
  (
    '스포위크 풋살 이벤트',
    'futsal-spoweek',
    'https://www.spoweek.com/event/list',
    'futsal',
    null,
    'board',
    'futsal-spoweek-list',
    '30 20 * * *',
    false,
    '민간 이벤트 플랫폼. 풋살 외 종목 혼재 — sport 필터링 필요. 전국 대회 다수.'
  ),
  (
    '경기도풋살연합회 대회공지',
    'futsal-ggfutsal',
    'http://www.ggfutsal.com/inobbs/bbs_list3.php?code=sbg_001&nbd=sbg_001&dbcal=no&lng=kor',
    'futsal',
    '경기',
    'board',
    'futsal-ggfutsal-board',
    '0 21 * * *',
    false,
    '경기도풋살연합회. PHP bbs 구조로 파싱 용이. 경기도 지역 대회 중심.'
  ),
  (
    '서울시민리그 S리그 풋살',
    'futsal-sleague',
    'https://www.sleague.or.kr/kr/sports/futsal.php',
    'futsal',
    '서울',
    'board',
    'futsal-sleague-page',
    '0 19 * * *',
    false,
    '서울특별시 공공 리그. 연 1회 시즌. 참가 접수 기간이 짧으므로 모니터링 필요.'
  ),
  (
    '위밋업 풋살 이벤트',
    'futsal-wemeetup',
    'https://www.wemeetup.org/event',
    'futsal',
    null,
    'board',
    'futsal-wemeetup-list',
    '30 19 * * *',
    false,
    '사단법인 위밋업. 여성 중심 풋살 대회(언니들축구대회 등) 포함. 비로그인 열람 가능.'
  )
on conflict (slug) do nothing;
