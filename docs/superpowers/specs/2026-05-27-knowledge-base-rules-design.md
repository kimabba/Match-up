# 지식베이스 1단계 — 룰북·지식 문서 관리 설계

날짜: 2026-05-27
상태: 설계 승인 → 구현 계획 대기

## Context

챗봇(RAG)과 대회 기능이 활용하는 정보를 관리자가 체계적으로 확인·검토·수정·활용할 **백오피스(지식베이스)**가 필요하다. 이는 앱 사용자용이 아니라 운영자용 시스템이다.

현재 챗봇 RAG가 참조하는 정보는 `rule_articles`(룰북, 임베딩)와 `intent_examples`(의도 분류)인데, **둘 다 관리 UI가 전혀 없어** DB·스크립트로만 다룬다. 어드민 콘솔(`admin_screen.dart`)에는 크롤/검수 탭만 있다.

지식베이스는 세 영역으로 단계적으로 구축한다:
1. **(이 문서) 룰북·지식 문서 관리** — `rule_articles` CRUD
2. 의도분류 예시 관리 — `intent_examples` (후속)
3. Q&A 캐시·챗봇 품질 모니터링 — `qa_cache`/`chat_messages` (후속)

또한 어드민 콘솔의 사이드바형 IA 재설계는 별도 후속 작업이다. 이번 1단계는 기존 탭 구조에 "지식베이스" 탭을 추가하되, 모놀리식(1485줄) `admin_screen.dart`에서 **별도 파일로 분리**해 점진적 리팩토링을 시작한다.

## 범위

### 포함 (1단계)
- `rule_articles` 목록 조회 (종목·카테고리 필터, published 무관 전체)
- 문서 작성/수정/삭제 (sport·category·title·body 마크다운·order_idx·published)
- 게시(published) 토글
- 임베딩 상태 표시 (최신 / 대기 / stale) + 수동 재계산
- 어드민 "지식베이스" 탭 신설 (별도 파일)

### 제외 (후속)
- 의도분류 예시(`intent_examples`) 관리 — 2단계
- Q&A 캐시·챗봇 품질 모니터링 — 3단계
- 어드민 콘솔 사이드바 IA 전면 재설계
- 지식 검색 테스트(semantic-search 미리보기)
- `embed-pending` 즉시 호출(현재는 5분 cron 재계산에 의존)

## 데이터 모델

**신규 마이그레이션 없음.** 기존 `rule_articles`(005_chat_rules.sql)를 그대로 사용:
```
id, sport(enum), category(text 자유), title, body(markdown),
order_idx(int), published(bool),
embedding vector(768), embedding_updated_at, created_at, updated_at
```
- RLS: `rule_articles_admin_all`(admin 전체 CRUD) + `rule_articles_authenticated_read`(published read) — **이미 존재**
- 트리거 `invalidate_rule_embedding()`: title/body 변경 시 `embedding=null` 자동 설정 — **이미 존재**. embed-pending(5분 cron)이 재계산.

## 백엔드

**신규 Edge Function 없음.** Flutter가 admin RLS로 `rule_articles`를 직접 CRUD (clubMembers 직접 select 패턴과 동일).
- 수동 재계산: 해당 행 `embedding=null, embedding_updated_at=null`로 update(admin RLS) → 기존 `embed-pending` cron이 다음 주기에 재계산.

## Flutter

### API (`app/lib/services/api.dart`)
- `adminListRules({String? sport})` — `_supabase.from('rule_articles').select()` 전체(published 무관), 정렬 `sport, category, order_idx`
- `createRule(Map)` / `updateRule(id, Map)` / `deleteRule(id)` — 직접 supabase
- `recomputeRuleEmbedding(id)` — embedding/embedding_updated_at을 null로 update

### Model (`app/lib/models/`)
- 기존 `RuleArticle` 모델 확장: `published`, `orderIdx`, `embedding` 유무(또는 `embeddingUpdatedAt`), `updatedAt` 추가 — 임베딩 상태 판정용. (현재 모델 필드 확인 후 누락분만 추가)

### Providers (`app/lib/state/providers.dart`)
- `adminRulesProvider` (FutureProvider.autoDispose, 종목 필터 시 family) — admin 전체 룰 목록

### 화면 (`app/lib/screens/admin/knowledge_base_tab.dart` 신규)
- `admin_screen.dart`의 탭 목록에 "지식베이스" 추가, 본문은 신규 파일 위젯
- 구성:
  - 상단: 종목/카테고리 필터
  - 목록: 카드/타일 — 제목·카테고리·게시여부·**임베딩 상태 뱃지**. 탭 시 편집
  - 편집 화면/다이얼로그: sport(SegmentedButton), category(text), title, body(마크다운 멀티라인), order_idx, published(Switch) + 저장/삭제 + 수동 재계산 버튼
  - 신규 작성 FAB

### 임베딩 상태 판정 (UI)
- `embedding == null` → "임베딩 대기" (회색/주황)
- `embedding != null && embedding_updated_at < updated_at` → "재계산 필요(stale)" (주황)
- 그 외 → "최신" (녹색)

(주의: `embedding` vector를 클라이언트로 전부 받으면 무겁다 — select 시 `embedding`은 `embedding is null` 여부만 필요하므로, 컬럼을 직접 받기보다 `embedding_updated_at`·`updated_at` 비교 + 별도 `has_embedding` 표현을 쓰거나, select에서 embedding 제외하고 `embedding_updated_at` null 여부로 판정. 구현 시 embedding 컬럼은 select하지 않는다.)

## 검증

- `flutter analyze` + `flutter test`
- admin 계정 E2E: 문서 생성 → 목록 노출 → 수정(저장 후 임베딩 "대기"로 바뀌는지 DB 확인) → 5분 후 또는 수동 재계산 후 "최신" → 삭제
- 비-admin 계정에서 rule_articles write가 RLS로 차단되는지 (직접 supabase 호출 실패 확인)
- 게시 토글 off 시 앱 룰북 화면(`rules_screen`)·챗봇 RAG에서 제외되는지

## 미해결 / 주의
- 임베딩 즉시 재계산(저장 즉시 반영)은 5분 cron 의존이라 지연이 있다. 즉시성이 필요하면 `embed-pending`에 admin 인증 호출 경로 추가를 후속 검토.
- 카테고리는 자유 텍스트라 오타로 분산될 수 있음 — 기존 카테고리 자동완성(드롭다운)을 편집 UI에서 제공해 일관성 보조.
