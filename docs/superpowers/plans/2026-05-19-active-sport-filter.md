# 전역 활성 종목 필터 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 사용자의 primary 종목(`is_primary=true`)을 전역 필터로 적용해 대회·클럽·룰북이 자동으로 해당 종목만 표시되게 한다.

**Architecture:** `activeSportProvider`를 `userSportsProvider`에서 파생시켜 단일 소스로 관리. 각 화면은 이 provider를 watch해 자동 갱신되며, 수동 종목 칩 UI는 제거. 종목 변경은 프로필 → 온보딩 화면에서만 가능.

**Tech Stack:** Flutter/Riverpod (FutureProvider, Provider), Supabase PostgREST, Deno/TypeScript Edge Functions

---

## 파일 구조

| 파일 | 변경 |
|------|------|
| `app/lib/state/providers.dart` | `activeSportProvider` 추가, `selectedSportProvider` 제거, `homeTournamentsProvider` 수정 |
| `app/lib/screens/tournaments/tournaments_screen.dart` | 수동 종목 칩 제거, `_SportChipRow`/`selectedSportProvider` 참조 제거 |
| `app/lib/screens/clubs_screen.dart` | 종목 칩 제거, 로컬 `_sport` state 제거, `activeSportProvider` watch |
| `app/lib/screens/rules_screen.dart` | 단일 종목 fetch + 조건부 TabBar |
| `app/lib/screens/profile_screen.dart` | "주 종목" → "활성 종목 (필터 기준)" |
| `app/lib/screens/auth/onboarding_screen.dart` | Radio 레이블 수정 |
| `supabase/functions/chat/index.ts` | `UserSport` interface + select에 `is_primary` 추가, `buildSystemPrompt` 수정 |

---

## Task 1: `activeSportProvider` 추가 + `selectedSportProvider` 제거

**Files:**
- Modify: `app/lib/state/providers.dart`

### 현재 코드 (참고)
```dart
// line 54-63
/// 현재 홈에서 보고 있는 종목 (다중 종목 사용자가 토글)
final selectedSportProvider = StateProvider<String?>((ref) => null);

/// 홈 자동 필터 결과
final homeTournamentsProvider = FutureProvider<List<Tournament>>((ref) async {
  ref.watch(authStateProvider);
  final api = ref.watch(apiProvider);
  final sport = ref.watch(selectedSportProvider);
  return api.searchTournaments(sport: sport, onlyMyGrade: true, limit: 50);
});
```

- [ ] **Step 1: `selectedSportProvider` 제거 + `activeSportProvider` + `homeTournamentsProvider` 수정**

`app/lib/state/providers.dart` lines 54-63을 아래로 교체:

```dart
/// 사용자의 primary 종목 — 앱 전체 필터 기준
/// userSportsProvider에서 파생, 별도 상태 없음
final activeSportProvider = Provider<String?>((ref) {
  final sports = ref.watch(userSportsProvider).valueOrNull ?? [];
  return sports.where((s) => s.isPrimary).firstOrNull?.sport;
});

/// 홈 자동 필터 결과 (activeSportProvider 기반)
final homeTournamentsProvider = FutureProvider<List<Tournament>>((ref) async {
  ref.watch(authStateProvider);
  final api = ref.watch(apiProvider);
  final sport = ref.watch(activeSportProvider);
  return api.searchTournaments(sport: sport, onlyMyGrade: true, limit: 50);
});
```

- [ ] **Step 2: 분석 통과 확인**

```bash
cd /Users/ssfak/Documents/01-github/Match-up/app && flutter analyze
```

Expected: `selectedSportProvider` 참조가 남아 있어 오류 발생 — 다음 Task에서 제거하므로 정상.

- [ ] **Step 3: 스테이징 (Task 2 완료 후 함께 커밋)**

```bash
cd /Users/ssfak/Documents/01-github/Match-up
git add app/lib/state/providers.dart
# Task 2에서 selectedSportProvider 참조를 모두 제거한 후 함께 커밋한다.
# 분석 오류가 있는 상태로 단독 커밋하지 않는다.
```

---

## Task 2: 대회 탭 — 종목 칩 제거 + `activeSportProvider` 사용

**Files:**
- Modify: `app/lib/screens/tournaments/tournaments_screen.dart`

### 현재 코드 (참고)
- line 21: `String? _sport;` (로컬 상태)
- lines 107-134: 수동 종목 칩 3개 (전체 종목/테니스/풋살)
- line 211: `final selected = ref.watch(selectedSportProvider);`
- lines 227-234: `_SportChipRow` + `selectedSportProvider.notifier` write
- lines 280-306: `_SportChipRow` 위젯 정의

- [ ] **Step 1: `_TournamentsScreenState`에서 수동 종목 칩 제거**

`_TournamentsScreenState`:
- `String? _sport;` (line 21) 제거
- `_search()` 내부 `sport: _sport` → `sport: ref.read(activeSportProvider)`로 변경
- `initState`에서 `_search()` 호출 직전 종목을 activeSportProvider에서 읽도록:

```dart
// _TournamentsScreenState 변경 후
String _q = '';
bool _onlyMyGrade = false;
List<Tournament>? _results;
bool _loading = false;

Future<void> _search() async {
  setState(() => _loading = true);
  final api = ref.read(apiProvider);
  final sport = ref.read(activeSportProvider); // activeSportProvider 사용
  final res = await api.searchTournaments(
    sport: sport,
    onlyMyGrade: _onlyMyGrade,
    query: _q,
    limit: 100,
  );
  if (mounted) {
    setState(() {
      _results = res;
      _loading = false;
    });
  }
}
```

- [ ] **Step 2: 수동 종목 칩 Row 제거**

lines 100-137 (AppChip "전체 종목", "테니스", "풋살" Row) 전체 삭제.
검색창 바로 아래 SizedBox(height: AppSpacing.sm) + 필터 칩 Row 블록 제거.
내 등급 Switch Row만 남김:

```dart
// 변경 후 필터 영역 (검색창 + 내등급 스위치만)
Column(
  children: [
    TextField(...), // 검색창 유지
    const SizedBox(height: AppSpacing.sm),
    Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Transform.scale(
          scale: 0.85,
          child: Switch(
            value: _onlyMyGrade,
            onChanged: (v) {
              setState(() => _onlyMyGrade = v);
              _search();
            },
          ),
        ),
        Text('내 등급', style: Theme.of(context).textTheme.labelMedium),
      ],
    ),
  ],
),
```

- [ ] **Step 3: `_MyGradeSection` — `selectedSportProvider` 참조 제거**

`_MyGradeSection.build()` 내:
- line 211 `final selected = ref.watch(selectedSportProvider);` 삭제
- lines 215 `showToggle` 조건 블록 삭제 (`sports.length > 1` 체크)
- lines 227-234 `if (showToggle) _SportChipRow(...)` 블록 삭제

```dart
// 변경 후 _MyGradeSection.build() 헤더
@override
Widget build(BuildContext context, WidgetRef ref) {
  final tournaments = ref.watch(homeTournamentsProvider);
  final favorites = ref.watch(favoriteIdsProvider);
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
        child: Text('내 등급 추천 대회', style: tt.titleMedium),
      ),
      tournaments.when(
        // ... 기존 로직 유지
      ),
      Divider(color: cs.outlineVariant, height: 1),
    ],
  );
}
```

- [ ] **Step 4: `_SportChipRow` 위젯 클래스 전체 삭제** (lines 280-306)

- [ ] **Step 5: 사용하지 않는 변수/import 정리**

`_MyGradeSection.build()` 에서 `sports` 변수(`ref.watch(userSportsProvider)`)를 사용하는 곳이 모두 제거됐으면 해당 라인도 삭제.
이후 `userSportsProvider` import가 파일 내 어디서도 쓰이지 않으면 import 라인도 제거.

- [ ] **Step 6: flutter analyze**

```bash
cd /Users/ssfak/Documents/01-github/Match-up/app && flutter analyze
```

Expected: No issues.

- [ ] **Step 7: 커밋 (Task 1 스테이징 파일과 함께)**

```bash
cd /Users/ssfak/Documents/01-github/Match-up
git add app/lib/screens/tournaments/tournaments_screen.dart
git commit -m "feat: activeSportProvider 도입 — 대회 탭 수동 종목 칩 제거"
```

---

## Task 3: 클럽 탭 — 종목 칩 제거 + reactive 필터

**Files:**
- Modify: `app/lib/screens/clubs_screen.dart`

### 변경 전략
`ConsumerStatefulWidget` 유지하되 로컬 `_sport` state 제거. `_load()`가 `activeSportProvider`를 직접 read. `build()`에서 `activeSportProvider`를 watch해 변경 시 `_load()` 재호출.

- [ ] **Step 1: `_sport` 로컬 state 제거 + `_load()` 수정**

```dart
class _ClubsScreenState extends ConsumerState<ClubsScreen> {
  // String? _sport; // 제거
  String _q = '';
  List<Club>? _clubs;
  bool _loading = false;

  Future<void> _load() async {
    setState(() => _loading = true);
    final sport = ref.read(activeSportProvider); // activeSportProvider 사용
    final list = await ref.read(apiProvider).searchClubs(sport: sport, q: _q);
    if (mounted) {
      setState(() {
        _clubs = list;
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    // activeSportProvider watch → 변경 시 rebuild → _load() 호출
    ref.listen(activeSportProvider, (_, __) => _load());
    // ... 이하 동일
  }
}
```

- [ ] **Step 2: 종목 칩 Row 제거**

`build()` 내 lines 78-109 (AppChip "전체"/"테니스"/"풋살" Row) 전체 삭제.
`const SizedBox(height: AppSpacing.sm)` (line 77) 도 함께 삭제.

- [ ] **Step 3: flutter analyze**

```bash
cd /Users/ssfak/Documents/01-github/Match-up/app && flutter analyze
```

Expected: No issues.

- [ ] **Step 4: 커밋**

```bash
cd /Users/ssfak/Documents/01-github/Match-up
git add app/lib/screens/clubs_screen.dart
git commit -m "feat(clubs): 종목 칩 제거, activeSportProvider 자동 필터"
```

---

## Task 4: 룰북 탭 — 단일 종목 뷰 + 조건부 TabBar

**Files:**
- Modify: `app/lib/screens/rules_screen.dart`

### 변경 전략
`activeSportProvider`가 있으면 해당 종목 1개만 fetch + 단일 ListView. `null`이면 기존 TabBar 유지.

- [ ] **Step 1: `_RulesScreenState` 수정**

```dart
class _RulesScreenState extends ConsumerState<RulesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  Map<String, List<RuleArticle>>? _tennisByCat;
  Map<String, List<RuleArticle>>? _futsalByCat;
  Map<String, List<RuleArticle>>? _activeByCat; // 단일 종목용
  bool _loading = true;
  String? _activeSport; // 로드 시점의 activeSport 저장

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(apiProvider);
    final sport = ref.read(activeSportProvider); // 단일 read (로드 시점)
    _activeSport = sport;

    if (sport != null) {
      // 활성 종목만 fetch
      final rules = await api.listRules(sport);
      if (!mounted) return;
      setState(() {
        _activeByCat = _groupByCategory(rules);
        _loading = false;
      });
    } else {
      // 미등록: 두 종목 모두 fetch
      final tennis = await api.listRules('tennis');
      final futsal = await api.listRules('futsal');
      if (!mounted) return;
      setState(() {
        _tennisByCat = _groupByCategory(tennis);
        _futsalByCat = _groupByCategory(futsal);
        _loading = false;
      });
    }
  }
```

- [ ] **Step 2: `build()` 수정 — 조건부 TabBar**

```dart
@override
Widget build(BuildContext context) {
  final cs = Theme.of(context).colorScheme;

  // activeSportProvider 변경 감지 → 재로드
  ref.listen(activeSportProvider, (_, __) {
    setState(() => _loading = true);
    _load();
  });

  if (_loading) {
    return Scaffold(
      appBar: AppBar(title: const Text('룰북')),
      body: const Center(child: CircularProgressIndicator()),
    );
  }

  // 활성 종목 있음: 단일 ListView
  if (_activeSport != null && _activeByCat != null) {
    return Scaffold(
      appBar: AppBar(title: const Text('룰북')),
      body: _CategoryList(grouped: _activeByCat),
    );
  }

  // 미등록: 기존 TabBar
  return Scaffold(
    appBar: AppBar(
      title: const Text('룰북'),
      bottom: TabBar(
        controller: _tab,
        tabs: const [
          Tab(icon: Icon(Icons.sports_tennis_rounded), text: '테니스'),
          Tab(icon: Icon(Icons.sports_soccer_rounded), text: '풋살'),
        ],
        indicatorColor: cs.primary,
        labelColor: cs.primary,
        unselectedLabelColor: cs.onSurfaceVariant,
      ),
    ),
    body: TabBarView(
      controller: _tab,
      children: [
        _CategoryList(grouped: _tennisByCat),
        _CategoryList(grouped: _futsalByCat),
      ],
    ),
  );
}
```

- [ ] **Step 3: flutter analyze**

```bash
cd /Users/ssfak/Documents/01-github/Match-up/app && flutter analyze
```

Expected: No issues.

- [ ] **Step 4: 커밋**

```bash
cd /Users/ssfak/Documents/01-github/Match-up
git add app/lib/screens/rules_screen.dart
git commit -m "feat(rules): activeSportProvider 기반 단일 종목 뷰, 미등록 시 TabBar 유지"
```

---

## Task 5: 프로필 + 온보딩 — 레이블 수정

**Files:**
- Modify: `app/lib/screens/profile_screen.dart` (line 278)
- Modify: `app/lib/screens/auth/onboarding_screen.dart` (line 311)

- [ ] **Step 1: profile_screen.dart line 278 수정**

```dart
// 변경 전
child: Text(
  '주 종목',
  ...
),

// 변경 후
child: Text(
  '활성 종목 (필터 기준)',
  ...
),
```

- [ ] **Step 2: onboarding_screen.dart line 311 수정**

```dart
// 변경 전
Text(
  '주 종목',
  style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
),

// 변경 후
Text(
  '앱 기본 종목 (대회·클럽·룰북 필터에 사용됩니다)',
  style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
),
```

- [ ] **Step 3: flutter analyze + flutter test**

```bash
cd /Users/ssfak/Documents/01-github/Match-up/app && flutter analyze && flutter test
```

Expected: All tests pass, no issues.

- [ ] **Step 4: 커밋**

```bash
cd /Users/ssfak/Documents/01-github/Match-up
git add app/lib/screens/profile_screen.dart app/lib/screens/auth/onboarding_screen.dart
git commit -m "feat(ux): 주 종목 레이블 → 활성 종목 / 앱 기본 종목"
```

---

## Task 6: chat Edge Function — primary 종목 강조

**Files:**
- Modify: `supabase/functions/chat/index.ts`

### 현재 코드 (참고)
```typescript
// line 26-29
interface UserSport {
  sport: string;
  grade: string;
}

// 사용자 sports 쿼리 (찾아서 확인 필요 — 대략 line 170)
.select('sport, grade')
```

- [ ] **Step 1: `UserSport` interface에 `is_primary` 추가**

```typescript
// 변경 후
interface UserSport {
  sport: string;
  grade: string;
  is_primary: boolean;
}
```

- [ ] **Step 2: `user_sports` 쿼리에 `is_primary` 추가**

`supabase/functions/chat/index.ts`에서 `.select('sport, grade')`를 찾아:
```typescript
.select('sport, grade, is_primary')
```

- [ ] **Step 3: `buildSystemPrompt()` 수정**

`buildSystemPrompt()` 함수 내 `profile` 생성 직후에 primary 종목 강조 추가:

```typescript
function buildSystemPrompt(sports: UserSport[], orgs: UserTennisOrgRow[]): string {
  const profile = sports.length === 0
    ? '아직 종목·등급을 등록하지 않았습니다.'
    : sports
        .map((s) =>
          `- ${SPORT_LABELS[s.sport as 'tennis' | 'futsal'] ?? s.sport}: ${
            GRADE_LABELS[s.grade] ?? s.grade
          }${s.is_primary ? ' (주요 관심 종목)' : ''}`
        )
        .join('\n');
  // 이하 기존 로직 유지
```

- [ ] **Step 4: deno lint**

```bash
cd /Users/ssfak/Documents/01-github/Match-up/supabase/functions && deno lint
```

Expected: No issues.

- [ ] **Step 5: 커밋**

```bash
cd /Users/ssfak/Documents/01-github/Match-up
git add supabase/functions/chat/index.ts
git commit -m "feat(chat): primary 종목 시스템 프롬프트에 강조 표시"
```

---

## 최종 검증

- [ ] `cd /Users/ssfak/Documents/01-github/Match-up/app && flutter analyze` — No issues
- [ ] `flutter test` — All tests pass
- [ ] `cd ../supabase/functions && deno lint` — No issues
- [ ] `make app` 실행 후 수동 확인:
  - 테니스 primary 계정: 대회·클럽 테니스만 표시, 룰북 테니스만 표시
  - 풋살 primary 계정: 풋살만 표시
  - 종목 미등록 계정: 전체 표시, 룰북 탭 유지
