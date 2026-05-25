-- 기존 잘못된 div1/div2/rookie eligible_grades 초기화
-- 크롤러가 새 {org}_{div} 코드 체계로 재크롤 시 정확한 값으로 채워짐

UPDATE tournaments
SET eligible_grades = '{}',
    division_label_local = null
WHERE sport = 'tennis'
  AND source IN ('tennis-gwangju', 'tennis-jeonnam')
  AND eligible_grades && ARRAY['div1','div2','div3','div4','div5','rookie'];

-- crawl_sources last_etag 초기화 → 다음 크롤 시 force new fetch
UPDATE crawl_sources
SET last_etag = null,
    last_modified = null
WHERE slug IN ('tennis-gwangju', 'tennis-jeonnam');
