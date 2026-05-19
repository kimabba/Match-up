# 설계: 채팅 메인화 + 어드민 패널 (2026-05-19)

## 개요

채팅을 앱의 진입점으로 승격하고, 어드민이 크롤 현황 모니터링·수동 실행·Draft 대회 승인을 한 화면에서 처리할 수 있는 관리 패널을 추가한다.

---

## 1. 내비게이션 구조 개편

### 현재
```
홈(/) | 대회(/tournaments) | 클럽(/clubs) | 스피드건(/speed-gun) | 룰북(/rules) | 챗봇(/chat) | 내정보(/profile)
```

### 변경 후
```
채팅(/) | 대회(/tournaments) | 클럽(/clubs) | 스피드건(/speed-gun, 비웹) | 룰북(/rules) | 내정보(/profile) | 어드민(/admin, admin 전용)
```

### 구현 상세

**`router.dart`:**
- `/` 빌더를 `ChatScreen`으로 교체
- `home_screen.dart` import 제거 (삭제된 파일)
- `/chat` 라우트 제거
- `/admin` 라우트 추가 (비어드민 접근 시 `/`로 redirect)
- `_MainShell`을 `StatelessWidget` → `ConsumerWidget`으로 변경
  - `_tabs` static getter에서 Riverpod `ref`를 받는 인스턴스 메서드로 전환
  - `isAdminProvider`를 watch해 어드민 탭 동적 삽입

**`/` 경로 변경 UX 영향:** 기존 `/` 홈 피드 북마크/딥링크는 채팅 화면으로 이동하게 됨 — 의도적 변경.

---

## 2. 어드민 role 확인 메커니즘

`supabase.auth.currentUser`는 `public.users.role`을 포함하지 않는다. 별도 provider를 추가한다.

### 추가: `isAdminProvider`

```dart
// state/providers.dart 에 추가
final isAdminProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return false;
  final supabase = ref.watch(supabaseProvider);
  final row = await supabase
      .from('users')
      .select('role')
      .eq('id', user.id)
      .single();
  return row['role'] == 'admin';
});
```

- 세션 변경 시 자동 재계산 (currentUserProvider 의존)
- 어드민 탭 노출 조건: `ref.watch(isAdminProvider).valueOrNull == true`
- `/admin` redirect 조건도 동일 provider 사용

---

## 3. 채팅 화면 빠른 명령어

### 동작
- 빈 대화 상태(`_messages.isEmpty`)에서만 표시
- 칩 탭 → 텍스트 설정 후 즉시 `_send()` 호출 (입력창 거치지 않음)

### 명령어 목록 (2열 그리드, 6개)
| 레이블 | 전송 메시지 |
|--------|------------|
| 이번 주말 내 등급 대회 | "이번 주말 내 등급에 맞는 대회 알려줘" |
| 테니스 서브 규칙 | "테니스 서브 기본 규칙 알려줘" |
| 광주 테니스 협회 정보 | "광주 테니스 협회 등급 체계와 대회 정보 알려줘" |
| 풋살 파울 규칙 | "풋살 누적 파울 규칙 알려줘" |
| 내 등급 클럽 추천 | "내 등급에 맞는 클럽 추천해줘" |
| 대회 신청 방법 | "동호인 테니스 대회 신청하는 방법 알려줘" |

### 코드 범위
- `chat_screen.dart` — `_EmptyHint` 위젯만 수정
- `_SuggestionChip`에 `onTap: VoidCallback` 추가
- `_ChatScreenState.sendText(String text)` 메서드 추출 (칩과 기존 `_send` 공유)

---

## 4. 대회 탭 — 홈 피드 흡수

### 변경
- `TournamentsScreen` 상단에 "내 등급 추천 대회" 섹션 추가
- 기존 `homeTournamentsProvider` + 스포츠 필터 칩을 `TournamentsScreen` 헤더로 이동
- 그 아래 기존 전체 대회 검색/필터 유지

### 코드 범위
- `tournaments_screen.dart` — 상단 섹션 추가
- `home_screen.dart` — 삭제

---

## 5. 어드민 패널

### 라우트
`/admin` — `isAdminProvider`가 true인 사용자에게만 탭 노출.
비어드민이 직접 접근 시 `router.dart` redirect에서 `/`로 보냄.

### 탭 구조
`AdminScreen`은 `TabBar` 3개 탭으로 구성.

#### 탭 1 — 크롤 현황
- `crawl_audit` 테이블 직접 조회 (`_supabase.from('crawl_audit')` — PostgREST, RLS admin_only 적용)
- 소스별 최근 5건 표시: 소스명, 상태 배지, 시작 시각, fetched/inserted/updated 카운트, 오류 메시지
- 30초 자동 새로고침: `TabController.addListener`로 탭 1이 선택된 경우에만 `Timer.periodic` 시작/취소

#### 탭 2 — Draft 승인
- `tournaments` 테이블에서 `status = 'draft'` 목록 조회
- 카드: 제목, 종목, 날짜, 지역, 소스 URL
- 액션: **승인** 버튼 / **거절** 버튼 (사유 텍스트 다이얼로그)
- 기존 `tournaments-approve` Edge Function 재사용
  - 승인: `action: 'approve'` → `status = 'published'`
  - 거절: `action: 'reject'` → `status = 'closed'` (기존 동작)
  - 참고: `status = 'closed'`는 거절된 대회와 기간 만료 대회가 공존함. `rejection_reason` 필드로 구분 가능하나 현재 설계 범위 밖.
- 승인/거절 후 목록 즉시 재조회 (`ref.invalidate(draftTournamentsProvider)`)

#### 탭 3 — 수동 실행
- 소스별 카드 3개: `crawl-tennis-gwangju`, `crawl-tennis-jeonnam`, `crawl-tennis-korea`
- "지금 실행" 버튼 → `invokeCrawler(source)` 호출
- 버튼 누르는 동안 스피너, 완료 시 결과 스낵바 (fetched/inserted/updated)
- 중복 방지: 실행 중 버튼 비활성화

### 크롤러 Edge Function 인증 처리 (필수 선행 작업)

현재 crawler Edge Functions에 auth guard가 없음. `invokeCrawler`를 안전하게 호출하기 위해:
- `crawl-tennis-gwangju`, `crawl-tennis-jeonnam`, `crawl-tennis-korea` 각각의 `index.ts` 시작 부분에 `requireAdmin(req)` 추가
- `_shared/auth.ts`에 `requireAdmin` 함수 추가 (기존 `requireUser` + role 검증)
- 이 변경이 없으면 수동 실행 탭은 구현하지 않음

### API 추가 (`api.dart`)

```dart
// CrawlAuditLog 모델 (models/admin.dart 신규 파일)
class CrawlAuditLog {
  final String id;
  final String source;
  final String status; // 'running' | 'success' | 'partial' | 'failed'
  final int fetchedCount;
  final int insertedCount;
  final int updatedCount;
  final String? error;
  final DateTime startedAt;
  final DateTime? finishedAt;

  CrawlAuditLog.fromJson(Map<String, dynamic> j) : ...;
}

// ApiService 추가 메서드
Future<List<CrawlAuditLog>> crawlAuditLogs({int limit = 30}) async {
  // _supabase.from('crawl_audit').select().order('started_at', ascending: false).limit(limit)
}

Future<Map<String, dynamic>> invokeCrawler(String source) async {
  // Edge Function HTTP POST — requireAdmin 선행 적용 전제
}
```

### 새 파일
- `app/lib/screens/admin/admin_screen.dart`
- `app/lib/models/admin.dart` (CrawlAuditLog 모델)

---

## 6. 변경 파일 요약

| 파일 | 작업 |
|------|------|
| `app/lib/router.dart` | `/` → ChatScreen, `home_screen.dart` import 제거, `/chat` 라우트 제거, `/admin` 라우트 추가, `_MainShell` ConsumerWidget 전환 |
| `app/lib/state/providers.dart` | `isAdminProvider` 추가 |
| `app/lib/screens/chat_screen.dart` | `_EmptyHint` 빠른 명령어 6개, 즉시 전송, `sendText` 메서드 추출 |
| `app/lib/screens/tournaments/tournaments_screen.dart` | 상단 내 등급 추천 섹션 추가 |
| `app/lib/screens/home_screen.dart` | 삭제 |
| `app/lib/screens/admin/admin_screen.dart` | 신규 — 3탭 어드민 패널 |
| `app/lib/models/admin.dart` | 신규 — CrawlAuditLog 모델 |
| `app/lib/services/api.dart` | `crawlAuditLogs()`, `invokeCrawler()` 추가 |
| `supabase/functions/_shared/auth.ts` | `requireAdmin()` 추가 |
| `supabase/functions/crawl-tennis-*/index.ts` | `requireAdmin(req)` guard 추가 (3개 파일) |
