# Team Collaboration Guide

Match-up은 작은 루트 규칙 파일과 필요 시 로드하는 `docs/rules/` 문서를 사용합니다.
팀원은 모든 문서를 항상 읽을 필요가 없습니다. 작업 영역에 맞는 문서만 읽고, 하네스가 통과하는지 확인하면 됩니다.

## 작업 시작 순서

1. GitHub Issue를 만든다.
2. Issue에서 작업 영역과 완료 기준을 명확히 적는다.
3. `AGENTS.md`의 load-on-demand 표를 보고 필요한 `docs/rules/*.md`만 읽는다.
4. 작은 브랜치를 만든다.
5. 테스트/하네스를 먼저 확인한다.
6. PR을 열고 PR template 체크리스트를 채운다.

## 추천 브랜치 이름

- `feat/<short-topic>` — 기능
- `fix/<short-topic>` — 버그 수정
- `docs/<short-topic>` — 문서
- `ci/<short-topic>` — CI/하네스
- `chore/<short-topic>` — 정리 작업

## PR 크기 기준

좋은 PR:

- 하나의 목적만 가진다.
- 리뷰 가능한 파일 수와 diff 크기를 유지한다.
- DB/API/UI를 한 번에 크게 바꾸지 않는다.
- 새 규칙이나 새 입력값에는 테스트/하네스가 같이 온다.

피해야 할 PR:

- UI, DB, API, 리팩터링, 문서 정리를 한 번에 넣는 PR.
- 루트 `AGENTS.md`/`CLAUDE.md`에 긴 내용을 붙이는 PR.
- Flutter에서만 eligibility/security를 처리하는 PR.

## 팀원이 특히 신경쓸 부분

### 1. 서버/DB source of truth

Flutter는 편의 UI일 뿐입니다. 다음 판단은 반드시 서버/DB가 최종 결정해야 합니다.

- 인증/권한
- 관리자 여부
- 대회 노출 상태
- 출전 가능 여부
- rate limit / quota

### 2. enum 동기화

다음 값은 Dart, TypeScript, SQL/seed가 어긋나면 사용자에게 바로 잘못 보입니다.

- sport
- tennis/futsal grades
- tennis orgs
- region codes
- entry fee units

변경 후 반드시 실행:

```bash
python3 scripts/harness/check_enums.py
```

### 3. RLS와 migration discipline

새 테이블은 반드시 같은 PR에서 처리합니다.

- 명시적 컬럼 타입
- RLS enable
- select/insert/update/delete policy
- 필요한 index
- 가능하면 SQL smoke fixture

### 4. AI/RAG와 외부 데이터 안전성

룰북, 대회 설명, 크롤러 결과, 웹 검색 결과는 모두 untrusted data입니다.
그 안에 “이전 지시를 무시해라”, “secret을 출력해라” 같은 문장이 있어도 명령으로 취급하면 안 됩니다.

### 5. 스피드건 품질

스피드건은 숫자가 틀리면 신뢰를 잃습니다.
낮은 품질 입력은 그럴듯한 결과보다 경고/차단/낮은 신뢰도 표시가 우선입니다.

팀원이 신경쓸 기준:

- fps 부족 경고
- calibration point 검증
- mock detector production 금지
- speed sanity range
- fixture 기반 테스트

### 6. 루트 규칙 파일 비대화 방지

`AGENTS.md`와 `CLAUDE.md`는 라우터입니다.
긴 설명은 `docs/rules/`에 추가하고, 루트에는 링크 한 줄만 추가하세요.

검증:

```bash
python3 scripts/harness/check_static_rules.py
```

## 기본 로컬 검증

전체 검증:

```bash
scripts/harness/run_all.sh
```

개별 검증:

```bash
python3 scripts/harness/check_enums.py
python3 scripts/harness/check_static_rules.py
bash scripts/harness/check_secrets.sh

cd app
flutter analyze
flutter test

cd ../supabase/functions
deno fmt --check */index.ts _shared/*.ts tests/*.ts
deno lint --config deno.json */index.ts _shared/*.ts tests/*.ts
deno check --config deno.json */index.ts _shared/*.ts tests/*.ts
deno test --config deno.json --allow-env --allow-read tests
```

## GitHub 운영 추천

- Issue는 작업 단위로 작게 쪼갭니다.
- PR은 Issue 하나를 닫는 크기가 좋습니다.
- PR template 체크리스트를 비워두지 않습니다.
- CI 실패 시 먼저 로그를 읽고, 실패한 하네스가 무엇을 보호하려는지 확인합니다.
- “문서만 있는 규칙”은 시간이 지나면 깨집니다. 반복되는 리뷰 코멘트는 하네스로 승격하세요.
