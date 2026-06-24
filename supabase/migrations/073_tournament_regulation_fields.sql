-- 073: 대회 요강 정형화 — regulation_fields / regulation_notes 추가
--
-- 배경:
--   협회 공고의 정의형 표(장소/주최/주관/후원/협찬/사용구/경기종목 …)가
--   크롤 시 구분자 없는 평문으로 뭉개져 description 에 저장되고,
--   앱이 런타임 정규식으로 재파싱하면서 자유 문장 안의 단어("안내","주최")를
--   라벨로 오인 → 한 문장이 두 행으로 쪼개지는 깨짐이 발생했다.
--
-- 해결:
--   크롤러가 원본 HTML <table> 의 라벨셀:값셀을 그대로 구조화 추출해
--   regulation_fields(순서 보존 배열) 에 저장하고, ※ 안내문은
--   regulation_notes 배열에 저장한다. 앱은 이 구조화 데이터를 표로 렌더한다.
--   description 은 RAG/임베딩용으로 유지(중복 보관).
--
-- 정형화 규칙:
--   regulation_fields jsonb = [{"label": "장소", "value": "..."}, ...]
--     - 원본 표 순서 보존
--     - 라벨 내부 공백 정규화 ("장 소" → "장소")
--     - 화이트리스트 라벨만 (장소/주최/주관/후원/협찬/시상/사용구/경기종목/경기방식 등)
--   regulation_notes text[] = ["참가비로 스포츠공제보험 가입", ...]
--     - "※" 로 시작하는 안내문, 마커 제거 후 트림
--
-- 노출:
--   상세 화면은 tournaments 를 select('*') 로 재조회하므로 컬럼 추가만으로 자동 노출된다.
--   목록 RPC(tournaments_for_user)는 요강을 쓰지 않으므로 수정하지 않는다.
--   tournaments 의 기존 RLS 정책이 신규 컬럼을 그대로 커버한다.

ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS regulation_fields jsonb,
  ADD COLUMN IF NOT EXISTS regulation_notes text[];

COMMENT ON COLUMN public.tournaments.regulation_fields IS
  '대회 요강 정형 필드. JSON 배열 [{label, value}], 원본 표 순서 보존, 화이트리스트 라벨만.';
COMMENT ON COLUMN public.tournaments.regulation_notes IS
  '대회 안내문(※ 항목) 배열. 보험/기금/기부/접수 등 자유 안내 문장.';
