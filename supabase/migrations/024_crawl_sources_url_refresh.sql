-- 024_crawl_sources_url_refresh.sql
--
-- 광주/전남 협회 사이트 리뉴얼 대응 + 한국테니스 일시 비활성화.
--
-- 변경 내역 (2026-05-21):
--   1) 광주: 옛 /board/list.php?bo_table=tournament 가 404 → /sub5_5.php (대회공지사항).
--   2) 전남: 옛 jntennis.or.kr 호스트 폐기, www.jntennis.kr 신규 호스트 + /sub5_5.php.
--   3) 한국: koreatennis.or.kr 도메인 자체가 DNS 해상 실패 (HTTP 000).
--      정확한 신규 URL 확인 전까지 enabled=false 로 비활성화 (dispatcher 자동 skip).
--   4) parser_module: 광주/전남이 동일 그누보드 변형 템플릿이라 'gnuboard-sub5-5-contest'
--      통합 parser 로 매핑 (registry.ts 참고). 옛 tennis-{gwangju,jeonnam,korea}-board
--      parser 모듈은 코드에서 제거됨.
--
-- 변경 감지(Phase 4):
--   대상 사이트가 ETag/Last-Modified 헤더를 내보내지 않아, parser 가 listing
--   콘텐츠 해시 W/"sha256:..." 를 last_etag 컬럼에 저장한다. dispatcher 가
--   다음 호출에서 If-None-Match 로 전달 → 동일 hash 면 no_change 처리.
--   기존 last_etag/last_modified 값은 reset (새 URL/구조와 무관).
--
-- 호환성:
--   thin wrapper edge functions (crawl-tennis-{gwangju,jeonnam,korea}) 도 본
--   PR 에서 제거됨. cron 은 이미 020 migration 에서 crawl-dispatch 로 일원화됨.

-- 메트릭(last_status/last_error/last_fetched_count) 도 함께 리셋:
-- 옛 URL 기반 에러가 어드민 UI 에 stale 하게 남는 걸 방지. 다음 dispatch 호출이
-- 새 URL/parser 기준으로 다시 채운다.

-- WHERE 절에 옛 parser_module 추가 — production 에서 admin 이 손으로 바꾼 source 는
-- 건드리지 않음 (rebase risk 회피, Codex B6).
update public.crawl_sources
set url = 'https://gjtennis.kr/sub5_5.php',
    parser_module = 'gnuboard-sub5-5-contest',
    last_etag = null,
    last_modified = null,
    last_status = null,
    last_error = null,
    last_fetched_count = null,
    notes = '2026-05-21: 사이트 리뉴얼 → 대회공지사항 게시판(sub5_5.php)으로 이동.'
where slug = 'tennis-gwangju'
  and parser_module = 'tennis-gwangju-board';

update public.crawl_sources
set url = 'https://www.jntennis.kr/sub5_5.php',
    parser_module = 'gnuboard-sub5-5-contest',
    last_etag = null,
    last_modified = null,
    last_status = null,
    last_error = null,
    last_fetched_count = null,
    notes = '2026-05-21: 도메인 변경 (jntennis.or.kr → www.jntennis.kr) + sub5_5.php.'
where slug = 'tennis-jeonnam'
  and parser_module = 'tennis-jeonnam-board';

-- tennis-korea: enabled=false + parser_module 도 통합 parser 로 정렬.
-- 옛 키 'tennis-korea-board' 그대로 두면 admin 이 재활성화 시 dispatcher 가
-- 'unknown parser_module' 에러 (Codex B5). 한국테니스도 광주/전남과 같은
-- 솔루션 가능성 → 신규 URL 확정 시 같은 parser 로 즉시 동작 검증 가능.
update public.crawl_sources
set enabled = false,
    parser_module = 'gnuboard-sub5-5-contest',
    last_etag = null,
    last_modified = null,
    last_status = null,
    last_error = null,
    last_fetched_count = null,
    notes = '2026-05-21: koreatennis.or.kr DNS 해상 실패. 정확한 신규 URL 확인 후 어드민 UI 에서 URL 갱신 + enabled=true 토글.'
where slug = 'tennis-korea'
  and parser_module = 'tennis-korea-board';
