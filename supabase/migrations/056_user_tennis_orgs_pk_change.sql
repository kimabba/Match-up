-- 056: user_tennis_orgs PK 변경 (user_id, org) → (user_id, org, division)
--
-- 변경 사항:
--   1. division text NOT NULL 컬럼 추가 (division_local 값 마이그레이션)
--   2. PK (user_id, org) → (user_id, org, division)
--   3. division_local, expires_at 컬럼 제거
--   4. score numeric(3,1) → numeric(5,1), CHECK 제약 제거
--   5. ranking_points int, player_origin text 추가
--   6. unique index 재생성: 협회+부서 조합별 primary 1개

BEGIN;

-- 1. division 컬럼 추가 (임시로 default 허용)
ALTER TABLE public.user_tennis_orgs
  ADD COLUMN division text NOT NULL DEFAULT 'default';

-- 2. 기존 division_local 값 복사
UPDATE public.user_tennis_orgs
  SET division = COALESCE(NULLIF(TRIM(division_local), ''), 'default');

-- 3. default 제거 (마이그레이션용 임시 default였으므로)
ALTER TABLE public.user_tennis_orgs
  ALTER COLUMN division DROP DEFAULT;

-- 4. 기존 PK 제거
ALTER TABLE public.user_tennis_orgs
  DROP CONSTRAINT user_tennis_orgs_pkey;

-- 5. 새 PK 설정
ALTER TABLE public.user_tennis_orgs
  ADD PRIMARY KEY (user_id, org, division);

-- 6. division_local 컬럼 제거
ALTER TABLE public.user_tennis_orgs
  DROP COLUMN division_local;

-- 7. expires_at 컬럼 제거
ALTER TABLE public.user_tennis_orgs
  DROP COLUMN expires_at;

-- 8. score CHECK 제약 제거 후 타입 변경
--    CHECK 이름은 테이블 생성 시 자동 생성된 이름을 사용
ALTER TABLE public.user_tennis_orgs
  DROP CONSTRAINT IF EXISTS user_tennis_orgs_score_check;
ALTER TABLE public.user_tennis_orgs
  ALTER COLUMN score TYPE numeric(5,1);

-- 9. ranking_points 컬럼 추가
ALTER TABLE public.user_tennis_orgs
  ADD COLUMN ranking_points int;

-- 10. player_origin 컬럼 추가
ALTER TABLE public.user_tennis_orgs
  ADD COLUMN player_origin text;

ALTER TABLE public.user_tennis_orgs
  ADD CONSTRAINT user_tennis_orgs_player_origin_check
  CHECK (player_origin IS NULL OR player_origin IN (
    'elementary', 'middle', 'high', 'university', 'professional', 'instructor'
  ));

-- 11. unique index 재생성
--     기존: (user_id) WHERE is_primary → 사용자 전체에서 primary 1개
--     변경: (user_id, org, division) WHERE is_primary → 불필요 (PK와 동일)
--     의도: 사용자당 primary 협회는 1개만 (org+division 조합 무관)
--     → 기존 인덱스 유지 (user_id WHERE is_primary)가 올바름
--     기존 인덱스가 이미 존재하므로 재생성 불필요

COMMIT;
