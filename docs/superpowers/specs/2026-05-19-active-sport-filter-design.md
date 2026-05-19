# 설계: 전역 활성 종목 필터 (2026-05-19)

## 개요

사용자가 가입 또는 프로필에서 선택한 primary 종목을 앱 전체의 기본 필터로 적용한다.
현재는 각 화면이 독립적인 수동 종목 칩을 갖거나 전체 종목을 동시에 표시해 사용자 의도와 무관한 콘텐츠가 섞인다.

---

## 1. 상태 설계

### 추가: `activeSportProvider`

```dart
// state/providers.dart
final activeSportProvider = Provider<String?>((ref) {
  final sports = ref.watch(userSportsProvider).valueOrNull ?? [];
  // Dart 3의 firstOrNull 사용 (package:collection 불필요)
  return sports.where((s) => s.isPrimary).firstOrNull?.sport;
  // 반환값: 'tennis' | 'futsal' | null(미등록)
});
```

- `userSportsProvider`에서 파생 — 별도 상태 없음
- Dart SDK >= 3.0의 `Iterable.firstOrNull` 사용 (외부 패키지 불필요)
- 세션 변경 / 프로필 수정 시 자동 재계산 (`userSportsProvider`가 invalidate되면 연쇄 갱신)

### 제거: `selectedSportProvider`

현재 `StateProvider<String?>`로 존재. `activeSportProvider`로 대체하며 완전 제거.

### 수정: `homeTournamentsProvider`

```dart
// 변경 전: selectedSportProvider 참조
final sport = ref.watch(selectedSportProvider);

// 변경 후: activeSportProvider 참조
final sport = ref.watch(activeSportProvider);
```

---

## 2. 화면별 변경

### 2-1. 대회 탭 (`tournaments_screen.dart`)

**현재:**
- `_MyGradeSection` 내부 `_SportChipRow` → `selectedSportProvider`를 write
- `ref.watch(selectedSportProvider)` + `ref.read(selectedSportProvider.notifier).state = s`

**변경:**
- `_SportChipRow` 위젯 및 `showToggle` 조건 블록 완전 제거
- `selectedSportProvider` 참조 2개 모두 제거 (line 211, 232)
- `_MyGradeSection`이 `activeSportProvider`를 watch (read-only, 변경 불가)
- 전체 검색 섹션의 수동 종목 칩("전체 종목 / 테니스 / 풋살")도 제거
- `activeSportProvider == null`이면 검색 파라미터 `sport: null` (전체 표시)

### 2-2. 클럽 탭 (`clubs_screen.dart`)

**현재:** 로컬 `String? _sport` state + 수동 종목 칩

**변경:**
- `clubs_screen.dart`를 `ConsumerStatefulWidget` → `ConsumerWidget`으로 전환 (로컬 sport state 제거)
- 또는 `ConsumerStatefulWidget` 유지 시 `_sport` 로컬 state 제거 후 `ref.watch(activeSportProvider)`를 직접 사용
- 종목 칩 UI 제거
- `activeSportProvider` 변경 시 자동 재로드: `ref.watch(activeSportProvider)`를 build 내에서 사용해 리액티브하게 동작
  - `initState`에서 시드하지 않음 — `build()` 내에서 watch해야 provider 변경에 반응함

```dart
// 변경 후 패턴 (ConsumerWidget 또는 ConsumerStatefulWidget의 build)
final activeSport = ref.watch(activeSportProvider);
// activeSport 변경 시 자동으로 _load() 재호출
```

- `activeSportProvider == null`이면 전체 클럽 표시

### 2-3. 룰북 탭 (`rules_screen.dart`)

**현재:** `_load()`에서 tennis/futsal 두 종목 모두 fetch, TabBar로 전환

**변경:**
- `activeSportProvider`가 있으면 해당 종목만 fetch + 단일 ListView 표시 (TabBar 제거)
- `activeSportProvider == null`이면 기존 TabBar 유지 (종목 미등록 사용자)
- 단일 종목만 fetch하므로 불필요한 네트워크 요청 제거

```dart
// 변경 후 _load() 패턴
final sport = ref.read(activeSportProvider);
if (sport != null) {
  _rules = await api.listRules(sport); // 단일 fetch
} else {
  // 기존: 두 종목 모두 fetch
}
```

### 2-4. 채팅 (`chat/index.ts`)

**Flutter 측:** 변경 없음 — 백엔드가 `user_sports`를 이미 조회함

**백엔드 수정 필요:**

```typescript
// 기존 interface
interface UserSport {
  sport: string;
  grade: string;
}

// 변경 후
interface UserSport {
  sport: string;
  grade: string;
  is_primary: boolean;
}

// 기존 쿼리
.select('sport, grade')

// 변경 후
.select('sport, grade, is_primary')
```

`buildSystemPrompt()`에 primary 종목 강조 추가:

```typescript
const primarySport = userSports.find(s => s.is_primary);
if (primarySport) {
  prompt += `\n사용자의 주요 관심 종목: ${primarySport.sport} (${primarySport.grade} 등급)`;
}
```

### 2-5. 프로필 (`profile_screen.dart`)

- 기존 `_SportCard`의 "주 종목" 배지를 "활성 종목 (필터 기준)"으로 레이블 변경
- "종목 변경" → 온보딩 화면으로 이동 (기존 동작 유지)
- `onboarding_screen.dart`의 `ref.invalidate(userSportsProvider)` (line 168) 이미 존재 → 추가 불필요

### 2-6. 온보딩 (`onboarding_screen.dart`)

- primary 라디오 버튼 레이블 수정:
  - `"주 종목"` → `"앱 기본 종목 (대회·클럽·룰북 필터에 사용됩니다)"`
- 그 외 변경 없음

---

## 3. 엣지 케이스

| 상황 | 처리 |
|------|------|
| 종목 미등록 (`activeSport == null`) | 전체 콘텐츠 표시, 온보딩 유도 배너 유지 |
| 단일 종목 등록 | 종목 칩/탭 UI 숨김 (불필요) |
| 두 종목 등록 | primary만 기본 표시, 프로필에서 primary 변경 가능 |
| primary 변경 | `userSportsProvider` invalidate (기존 코드) → `activeSportProvider` 자동 갱신 → 모든 화면 즉시 갱신 |

---

## 4. 변경 파일 요약

| 파일 | 변경 |
|------|------|
| `app/lib/state/providers.dart` | `activeSportProvider` 추가, `selectedSportProvider` 제거, `homeTournamentsProvider` 수정 |
| `app/lib/screens/tournaments/tournaments_screen.dart` | `_SportChipRow` + `selectedSportProvider` 참조 제거, 수동 종목 칩 제거, `activeSportProvider` 사용 |
| `app/lib/screens/clubs_screen.dart` | 종목 칩 제거, 로컬 `_sport` state 제거, `activeSportProvider` watch |
| `app/lib/screens/rules_screen.dart` | 단일 종목 fetch + ListView, 탭 조건부 표시 |
| `app/lib/screens/auth/onboarding_screen.dart` | primary 레이블 수정 |
| `app/lib/screens/profile_screen.dart` | "주 종목" → "활성 종목 (필터 기준)" 레이블 |
| `supabase/functions/chat/index.ts` | `UserSport` interface + select에 `is_primary` 추가, `buildSystemPrompt` 수정 |
