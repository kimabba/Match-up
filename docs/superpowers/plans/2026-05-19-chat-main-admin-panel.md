# 채팅 메인화 + 어드민 패널 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 채팅을 앱 메인 화면으로 승격하고, 어드민이 크롤 현황 모니터링·Draft 대회 승인·크롤러 수동 실행을 한 화면에서 처리할 수 있는 관리 패널을 추가한다.

**Architecture:** `router.dart`의 `/`를 ChatScreen으로 교체하고 `_MainShell`을 ConsumerWidget으로 전환해 `isAdminProvider` 기반 어드민 탭을 동적 삽입한다. 어드민 패널은 `TabBar` 3개 탭 구조로 `crawl_audit` PostgREST 직접 조회 + 기존 `tournaments-approve` Edge Function 재사용으로 구현한다. 크롤러 Edge Functions에는 이미 존재하는 `requireAdmin()` 가드를 적용한다.

**Tech Stack:** Flutter 3.x, Riverpod 2.x, go_router, Supabase (PostgREST + Edge Functions), Deno/TypeScript

---

## 파일 맵

| 파일 | 작업 |
|------|------|
| `supabase/functions/crawl-tennis-gwangju/index.ts` | Modify — requireAdmin 가드 추가 |
| `supabase/functions/crawl-tennis-jeonnam/index.ts` | Modify — requireAdmin 가드 추가 |
| `supabase/functions/crawl-tennis-korea/index.ts` | Modify — requireAdmin 가드 추가 |
| `app/lib/state/providers.dart` | Modify — isAdminProvider 추가 |
| `app/lib/router.dart` | Modify — _MainShell ConsumerWidget, 탭 재정렬, /admin 라우트 |
| `app/lib/screens/chat_screen.dart` | Modify — 빠른 명령어 6개 |
| `app/lib/screens/tournaments/tournaments_screen.dart` | Modify — 내 등급 추천 섹션 추가 |
| `app/lib/screens/home_screen.dart` | Delete |
| `app/lib/models/admin.dart` | Create — CrawlAuditLog 모델 |
| `app/lib/services/api.dart` | Modify — crawlAuditLogs(), invokeCrawler() |
| `app/lib/screens/admin/admin_screen.dart` | Create — 3탭 어드민 패널 |

---

## Task 1: 크롤러 Edge Function requireAdmin 가드 (SSF-301)

> `requireAdmin`은 `supabase/functions/_shared/auth.ts`에 이미 구현되어 있음.
> 3개 크롤러 파일 각각의 첫 번째 인증 체크 위치에 추가하면 된다.

**Files:**
- Modify: `supabase/functions/crawl-tennis-gwangju/index.ts`
- Modify: `supabase/functions/crawl-tennis-jeonnam/index.ts`
- Modify: `supabase/functions/crawl-tennis-korea/index.ts`

- [ ] **Step 1: crawl-tennis-gwangju에 requireAdmin 추가**

`supabase/functions/crawl-tennis-gwangju/index.ts`의 `Deno.serve` 핸들러 최상단:

```typescript
// 기존
import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
// ... 기존 imports ...

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;

  // ▼ 추가
  const auth = await requireAdmin(req);
  if ('error' in auth) return auth.error;
  // ▲ 추가

  const audit = await startAudit(SOURCE);
  // ... 이하 기존 코드 ...
```

import에도 `requireAdmin` 추가:
```typescript
import { requireAdmin } from '../_shared/auth.ts';
```

- [ ] **Step 2: crawl-tennis-jeonnam, crawl-tennis-korea 동일하게 적용**

두 파일도 동일한 패턴으로 `requireAdmin` import 추가 + 핸들러 첫 줄에 인증 체크 삽입.

- [ ] **Step 3: deno lint 통과 확인**

```bash
cd supabase/functions && deno lint
```

Expected: no errors

- [ ] **Step 4: 커밋**

```bash
git add supabase/functions/crawl-tennis-gwangju/index.ts \
        supabase/functions/crawl-tennis-jeonnam/index.ts \
        supabase/functions/crawl-tennis-korea/index.ts
git commit -m "feat(backend): 크롤러 Edge Function에 requireAdmin 인증 가드 추가"
```

---

## Task 2: isAdminProvider 추가 (SSF-302)

**Files:**
- Modify: `app/lib/state/providers.dart`
- Test: `app/test/providers_test.dart` (신규)

- [ ] **Step 1: isAdminProvider 추가**

`app/lib/state/providers.dart` 파일 끝에 추가:

```dart
/// public.users.role 을 읽어 어드민 여부 반환.
/// currentUserProvider 변경 시 자동 재계산.
final isAdminProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return false;
  final supabase = ref.watch(supabaseProvider);
  final row = await supabase
      .from('users')
      .select('role')
      .eq('id', user.id)
      .maybeSingle();
  return row?['role'] == 'admin';
});
```

> `.single()` 대신 `.maybeSingle()` 사용 — 행이 없을 때 예외 대신 null 반환.

- [ ] **Step 2: flutter analyze 통과**

```bash
cd app && flutter analyze
```

Expected: No issues found!

- [ ] **Step 3: 커밋**

```bash
git add app/lib/state/providers.dart
git commit -m "feat(flutter): isAdminProvider — DB role 기반 어드민 확인"
```

---

## Task 3: 내비게이션 개편 (SSF-303)

**Files:**
- Modify: `app/lib/router.dart`

- [ ] **Step 1: _MainShell을 ConsumerWidget으로 전환**

`router.dart`에서 `_MainShell` 클래스 전체 교체:

```dart
class _MainShell extends ConsumerWidget {
  const _MainShell({required this.child});
  final Widget child;

  List<(String, IconData, String)> _tabs(WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;
    return [
      ('/', Icons.chat_bubble_outline, '채팅'),
      ('/tournaments', Icons.emoji_events_outlined, '대회'),
      ('/clubs', Icons.groups_outlined, '클럽'),
      if (!kIsWeb) ('/speed-gun', Icons.speed_rounded, '스피드건'),
      ('/rules', Icons.menu_book_outlined, '룰북'),
      ('/profile', Icons.person_outline, '내정보'),
      if (isAdmin) ('/admin', Icons.admin_panel_settings_outlined, '어드민'),
    ];
  }

  int _indexOf(String location, List<(String, IconData, String)> tabs) {
    for (var i = 0; i < tabs.length; i++) {
      if (location == tabs[i].$1 ||
          (location.startsWith(tabs[i].$1) && tabs[i].$1 != '/')) {
        return i;
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = _tabs(ref);
    final loc = GoRouterState.of(context).matchedLocation;
    final idx = _indexOf(loc, tabs);
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => context.go(tabs[i].$1),
        destinations: [
          for (final t in tabs)
            NavigationDestination(icon: Icon(t.$2), label: t.$3),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: router.dart 라우트 수정**

```dart
// import 제거: home_screen.dart
// ⚠️ AdminScreen import와 /admin GoRoute는 Task 7에서 추가 (admin_screen.dart 생성 후)

// ShellRoute.routes 내부 변경 (ShellRoute 밖에 두면 하단 탭이 표시되지 않으니 주의):
GoRoute(path: '/', builder: (_, __) => const ChatScreen()),  // HomeScreen → ChatScreen
// '/chat' GoRoute 제거
```

redirect 함수에 어드민 체크 추가:

```dart
redirect: (context, state) async {
  final user = ref.read(currentUserProvider);
  final loc = state.matchedLocation;

  if (user == null) {
    return loc == '/login' ? null : '/login';
  }

  final sportsAsync = ref.read(userSportsProvider);
  if (sportsAsync.isLoading) return null;
  final sports = sportsAsync.valueOrNull ?? const [];
  if (sports.isEmpty && loc != '/onboarding') return '/onboarding';

  // /admin 비어드민 접근 차단
  if (loc == '/admin') {
    final isAdmin = ref.read(isAdminProvider).valueOrNull ?? false;
    if (!isAdmin) return '/';
  }

  if (loc == '/login') return '/';
  return null;
},
```

`GoRouterRefreshStream`에 `isAdminProvider` 리슨 추가:

```dart
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Ref ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
    ref.listen(userSportsProvider, (_, __) => notifyListeners());
    ref.listen(isAdminProvider, (_, __) => notifyListeners());  // 추가
  }
}
```

- [ ] **Step 3: home_screen.dart import 제거 확인**

`router.dart`에서 `home_screen.dart` import가 없는지 확인.

- [ ] **Step 4: flutter analyze 통과**

```bash
cd app && flutter analyze
```

Expected: No issues found!

- [ ] **Step 5: 커밋**

```bash
git add app/lib/router.dart
git commit -m "feat(flutter): 내비게이션 개편 — 채팅 메인, 어드민 탭 동적 노출"
```

---

## Task 4: 채팅 빠른 명령어 (SSF-304)

**Files:**
- Modify: `app/lib/screens/chat_screen.dart`

- [ ] **Step 1: sendText 메서드 추출 + _SuggestionChip onTap 추가**

`_ChatScreenState`에 메서드 추가:

```dart
Future<void> sendText(String text) async {
  _ctrl.text = text;
  await _send();
}
```

`_SuggestionChip` 클래스 수정:

```dart
class _SuggestionChip extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;  // 추가
  const _SuggestionChip(this.text, {this.onTap});  // 추가

  @override
  Widget build(BuildContext context) {
    // ... 기존 Container 코드 ...
    return GestureDetector(  // GestureDetector로 감싸기
      onTap: onTap,
      child: Container(
        // ... 기존 decoration 그대로 ...
      ),
    );
  }
}
```

- [ ] **Step 2: _EmptyHint를 6개 칩 2열 그리드로 교체**

`_EmptyHint.build` 내 제안 칩 부분을 교체.
그리고 `_ChatScreenState.build`에서 기존 `_EmptyHint()` 호출을 `_EmptyHint(onSend: sendText)`로 반드시 변경:

```dart
// 기존 _SuggestionChip 2개 제거하고 아래로 교체
const suggestions = [
  ('이번 주말 내 등급 대회', '이번 주말 내 등급에 맞는 대회 알려줘'),
  ('테니스 서브 규칙', '테니스 서브 기본 규칙 알려줘'),
  ('광주 테니스 협회 정보', '광주 테니스 협회 등급 체계와 대회 정보 알려줘'),
  ('풋살 파울 규칙', '풋살 누적 파울 규칙 알려줘'),
  ('내 등급 클럽 추천', '내 등급에 맞는 클럽 추천해줘'),
  ('대회 신청 방법', '동호인 테니스 대회 신청하는 방법 알려줘'),
];
```

`_EmptyHint`는 `ConsumerWidget`이 아니므로 `onSend` 콜백을 생성자로 받도록 수정:

```dart
class _EmptyHint extends StatelessWidget {
  final Future<void> Function(String) onSend;
  const _EmptyHint({required this.onSend});

  @override
  Widget build(BuildContext context) {
    // ...
    // 칩 부분:
    GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 3.0,
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      children: [
        for (final (label, msg) in suggestions)
          _SuggestionChip(label, onTap: () => onSend(msg)),
      ],
    ),
  }
}
```

`_ChatScreenState.build`에서 `_EmptyHint` 생성 시 콜백 전달:

```dart
_messages.isEmpty
    ? _EmptyHint(onSend: sendText)
    : ListView.builder(...)
```

- [ ] **Step 3: flutter analyze 통과**

```bash
cd app && flutter analyze
```

- [ ] **Step 4: 커밋**

```bash
git add app/lib/screens/chat_screen.dart
git commit -m "feat(flutter): 채팅 빠른 명령어 6개 — 칩 탭 즉시 전송"
```

---

## Task 5: 대회 탭 홈 피드 흡수 + HomeScreen 삭제 (SSF-305)

**Files:**
- Modify: `app/lib/screens/tournaments/tournaments_screen.dart`
- Delete: `app/lib/screens/home_screen.dart`

- [ ] **Step 1: homeTournamentsProvider 관련 imports 추가**

`tournaments_screen.dart` import에 추가:

```dart
import '../../utils/grade_labels.dart';
import '../../widgets/app_chip.dart';
import '../../widgets/tournament_card.dart';
```

(이미 있는 것은 중복 추가하지 않음)

- [ ] **Step 2: 추천 대회 섹션 위젯 추가**

`tournaments_screen.dart`에 private 위젯 추가:

```dart
class _MyGradeSection extends ConsumerWidget {
  const _MyGradeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sports = ref.watch(userSportsProvider);
    final tournaments = ref.watch(homeTournamentsProvider);
    final favorites = ref.watch(favoriteIdsProvider);
    final selected = ref.watch(selectedSportProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final showToggle = sports.maybeWhen(data: (l) => l.length > 1, orElse: () => false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Text('내 등급 추천 대회', style: tt.titleMedium),
              ),
              if (showToggle)
                _SportChipRow(
                  sports: sports.valueOrNull ?? const [],
                  selected: selected,
                  onChanged: (s) {
                    ref.read(selectedSportProvider.notifier).state = s;
                    ref.invalidate(homeTournamentsProvider);
                  },
                ),
            ],
          ),
        ),
        tournaments.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: CircularProgressIndicator(),
          ),
          error: (e, _) => const SizedBox.shrink(),
          data: (list) {
            if (list.isEmpty) return const SizedBox.shrink();
            final favs = favorites.valueOrNull ?? const <String>{};
            return SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, i) {
                  final t = list[i];
                  return SizedBox(
                    width: 260,
                    child: TournamentCard(
                      tournament: t,
                      isFavorite: favs.contains(t.id),
                      onTap: () => context.push('/tournaments/${t.id}'),
                      onFavoriteToggle: () async {
                        final api = ref.read(apiProvider);
                        await api.toggleFavorite(t.id, !favs.contains(t.id));
                        ref.invalidate(favoriteIdsProvider);
                      },
                    ),
                  );
                },
              ),
            );
          },
        ),
        Divider(color: cs.outlineVariant, height: 1),
      ],
    );
  }
}

class _SportChipRow extends StatelessWidget {
  final List<UserSport> sports;
  final String? selected;
  final ValueChanged<String?> onChanged;
  const _SportChipRow({required this.sports, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          AppChip(label: '전체', selected: selected == null, onTap: () => onChanged(null)),
          const SizedBox(width: AppSpacing.xs),
          ...sports.map((s) => Padding(
            padding: const EdgeInsets.only(left: AppSpacing.xs),
            child: AppChip(
              label: sportLabelFromString(s.sport),
              selected: selected == s.sport,
              onTap: () => onChanged(s.sport),
            ),
          )),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: TournamentsScreen body에 _MyGradeSection 삽입**

`_TournamentsScreenState.build`의 `body: Column(children: [` 최상단에 추가:

```dart
body: Column(
  children: [
    const _MyGradeSection(),  // ← 추가
    // 검색 + 필터 영역 (기존 Container)
    Container( ... ),
    // 결과 목록 (기존 Expanded)
    Expanded( ... ),
  ],
),
```

- [ ] **Step 4: home_screen.dart 파일 삭제**

```bash
rm app/lib/screens/home_screen.dart
```

- [ ] **Step 5: flutter analyze 통과**

```bash
cd app && flutter analyze
```

Expected: No issues found!

- [ ] **Step 6: 커밋**

```bash
git add app/lib/screens/tournaments/tournaments_screen.dart
git rm app/lib/screens/home_screen.dart
git commit -m "feat(flutter): 대회 탭에 내 등급 추천 섹션 추가, HomeScreen 삭제"
```

---

## Task 6: 어드민 패널 (SSF-306)

**Files:**
- Create: `app/lib/models/admin.dart`
- Modify: `app/lib/services/api.dart`
- Create: `app/lib/screens/admin/admin_screen.dart`

### Task 6-A: CrawlAuditLog 모델 + API

- [ ] **Step 1: admin.dart 모델 생성**

`app/lib/models/admin.dart`:

```dart
class CrawlAuditLog {
  final String id;
  final String source;
  final String status;
  final int fetchedCount;
  final int insertedCount;
  final int updatedCount;
  final String? error;
  final DateTime startedAt;
  final DateTime? finishedAt;

  CrawlAuditLog({
    required this.id,
    required this.source,
    required this.status,
    required this.fetchedCount,
    required this.insertedCount,
    required this.updatedCount,
    this.error,
    required this.startedAt,
    this.finishedAt,
  });

  factory CrawlAuditLog.fromJson(Map<String, dynamic> j) => CrawlAuditLog(
        id: j['id'] as String,
        source: j['source'] as String,
        status: j['status'] as String,
        fetchedCount: j['fetched_count'] as int? ?? 0,
        insertedCount: j['inserted_count'] as int? ?? 0,
        updatedCount: j['updated_count'] as int? ?? 0,
        error: j['error'] as String?,
        startedAt: DateTime.parse(j['started_at'] as String),
        finishedAt: j['finished_at'] != null
            ? DateTime.parse(j['finished_at'] as String)
            : null,
      );
}
```

- [ ] **Step 2: api.dart에 crawlAuditLogs + invokeCrawler 추가**

> 참고: `approveTournament(id, {bool approve, String? reason})` 메서드는 `api.dart` line 76에 이미 존재함. 추가 불필요.

`app/lib/services/api.dart`에 import 추가:
```dart
import '../models/admin.dart';
```

`ApiService`에 메서드 추가:

```dart
// ===== admin =====
Future<List<CrawlAuditLog>> crawlAuditLogs({int limit = 30}) async {
  final rows = await _supabase
      .from('crawl_audit')
      .select()
      .order('started_at', ascending: false)
      .limit(limit);
  return rows.map((r) => CrawlAuditLog.fromJson(r)).toList();
}

Future<Map<String, dynamic>> invokeCrawler(String source) async {
  final res = await http.post(
    _uri(source),
    headers: _authHeaders(),
  );
  _check(res);
  return jsonDecode(res.body) as Map<String, dynamic>;
}
```

- [ ] **Step 3: flutter analyze 통과**

```bash
cd app && flutter analyze
```

- [ ] **Step 4: 커밋**

```bash
git add app/lib/models/admin.dart app/lib/services/api.dart
git commit -m "feat(flutter): CrawlAuditLog 모델 + crawlAuditLogs/invokeCrawler API"
```

### Task 6-B: AdminScreen 구현

- [ ] **Step 1: admin_screen.dart 생성**

`app/lib/screens/admin/admin_screen.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/admin.dart';
import '../../models/tournament.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  Timer? _refreshTimer;
  List<CrawlAuditLog> _logs = [];
  List<Tournament> _drafts = [];
  bool _logsLoading = false;
  bool _draftsLoading = false;
  final Set<String> _invoking = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(_onTabChanged);
    _loadLogs();
    _loadDrafts();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tab.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tab.index == 0) {
      _startAutoRefresh();
    } else {
      _refreshTimer?.cancel();
    }
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadLogs(),
    );
  }

  Future<void> _loadLogs() async {
    if (!mounted) return;
    setState(() => _logsLoading = true);
    try {
      final logs = await ref.read(apiProvider).crawlAuditLogs();
      if (mounted) setState(() => _logs = logs);
    } finally {
      if (mounted) setState(() => _logsLoading = false);
    }
  }

  Future<void> _loadDrafts() async {
    if (!mounted) return;
    setState(() => _draftsLoading = true);
    try {
      final rows = await ref.read(supabaseProvider)
          .from('tournaments')
          .select()
          .eq('status', 'draft')
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() => _drafts = rows.map((r) => Tournament.fromJson(r)).toList());
      }
    } finally {
      if (mounted) setState(() => _draftsLoading = false);
    }
  }

  Future<void> _approve(String id) async {
    await ref.read(apiProvider).approveTournament(id, approve: true);
    await _loadDrafts();
  }

  Future<void> _reject(String id) async {
    final reason = await _showReasonDialog();
    if (reason == null) return;
    await ref.read(apiProvider).approveTournament(id, approve: false, reason: reason);
    await _loadDrafts();
  }

  Future<String?> _showReasonDialog() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('거절 사유'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: '사유를 입력하세요'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _invokeCrawler(String source) async {
    setState(() => _invoking.add(source));
    try {
      final result = await ref.read(apiProvider).invokeCrawler(source);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          '$source 완료: fetched=${result['fetched']}, '
          'inserted=${result['inserted']}, updated=${result['updated']}',
        ),
      ));
      await _loadLogs();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('실패: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _invoking.remove(source));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('어드민'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: '크롤 현황'),
            Tab(text: 'Draft 승인'),
            Tab(text: '수동 실행'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _CrawlLogsTab(logs: _logs, loading: _logsLoading, onRefresh: _loadLogs),
          _DraftApprovTab(
            drafts: _drafts,
            loading: _draftsLoading,
            onApprove: _approve,
            onReject: _reject,
          ),
          _ManualRunTab(invoking: _invoking, onRun: _invokeCrawler),
        ],
      ),
    );
  }
}

// ── 탭 1: 크롤 현황 ────────────────────────────────────────

class _CrawlLogsTab extends StatelessWidget {
  final List<CrawlAuditLog> logs;
  final bool loading;
  final VoidCallback onRefresh;
  const _CrawlLogsTab({required this.logs, required this.loading, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (loading && logs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: logs.isEmpty
          ? const Center(child: Text('크롤 이력 없음'))
          : ListView.builder(
              itemCount: logs.length,
              itemBuilder: (_, i) => _CrawlLogTile(log: logs[i]),
            ),
    );
  }
}

class _CrawlLogTile extends StatelessWidget {
  final CrawlAuditLog log;
  const _CrawlLogTile({required this.log});

  Color _statusColor(BuildContext context, String status) {
    final cs = Theme.of(context).colorScheme;
    return switch (status) {
      'success' => Colors.green,
      'partial' => Colors.orange,
      'failed' => cs.error,
      _ => cs.outline,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return ListTile(
      leading: Container(
        width: 10,
        height: 10,
        margin: const EdgeInsets.only(top: 4),
        decoration: BoxDecoration(
          color: _statusColor(context, log.status),
          shape: BoxShape.circle,
        ),
      ),
      title: Text(log.source, style: tt.bodyMedium),
      subtitle: Text(
        '${log.startedAt.toLocal().toString().substring(0, 16)}'
        ' · fetched ${log.fetchedCount} / +${log.insertedCount} / ↑${log.updatedCount}',
        style: tt.labelSmall,
      ),
      trailing: log.error != null
          ? Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error, size: 16)
          : null,
    );
  }
}

// ── 탭 2: Draft 승인 ───────────────────────────────────────

class _DraftApprovTab extends StatelessWidget {
  final List<Tournament> drafts;
  final bool loading;
  final Future<void> Function(String) onApprove;
  final Future<void> Function(String) onReject;
  const _DraftApprovTab({
    required this.drafts,
    required this.loading,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (drafts.isEmpty) return const Center(child: Text('승인 대기 대회 없음'));
    return ListView.builder(
      itemCount: drafts.length,
      itemBuilder: (_, i) => _DraftTile(
        tournament: drafts[i],
        onApprove: () => onApprove(drafts[i].id),
        onReject: () => onReject(drafts[i].id),
      ),
    );
  }
}

class _DraftTile extends StatelessWidget {
  final Tournament tournament;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  const _DraftTile({required this.tournament, required this.onApprove, required this.onReject});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tournament.title, style: tt.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${tournament.sport} · ${tournament.region ?? '지역미상'} · ${tournament.startDate.toString().substring(0, 10)}',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (tournament.sourceUrl != null)
              Text(
                tournament.sourceUrl!,
                style: tt.labelSmall?.copyWith(color: cs.primary),
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                  child: const Text('거절'),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(onPressed: onApprove, child: const Text('승인')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── 탭 3: 수동 실행 ────────────────────────────────────────

class _ManualRunTab extends StatelessWidget {
  final Set<String> invoking;
  final Future<void> Function(String) onRun;
  const _ManualRunTab({required this.invoking, required this.onRun});

  static const _sources = [
    ('crawl-tennis-gwangju', '광주 테니스'),
    ('crawl-tennis-jeonnam', '전남 테니스'),
    ('crawl-tennis-korea', 'KTA 테니스'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        for (final (source, label) in _sources)
          Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            child: ListTile(
              title: Text(label),
              subtitle: Text(source),
              trailing: invoking.contains(source)
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : FilledButton.tonal(
                      onPressed: () => onRun(source),
                      child: const Text('지금 실행'),
                    ),
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 2: Tournament 모델에 sourceUrl, startDate 필드 확인**

`app/lib/models/tournament.dart`에서 `source_url`, `start_date` 필드가 있는지 확인.
없으면 `Tournament.fromJson`에 추가 (nullable String으로).

- [ ] **Step 3: flutter analyze 통과**

```bash
cd app && flutter analyze
```

- [ ] **Step 4: 커밋**

```bash
git add app/lib/screens/admin/admin_screen.dart
git commit -m "feat(flutter): 어드민 패널 — 크롤 현황/Draft 승인/수동 실행"
```

---

## Task 7: router에 AdminScreen 연결 + 최종 검증

**Files:**
- Modify: `app/lib/router.dart`

- [ ] **Step 1: AdminScreen import + /admin GoRoute 추가**

`router.dart`에 import 추가:
```dart
import 'screens/admin/admin_screen.dart';
```

`ShellRoute.routes` **내부**에 `/admin` 추가 (ShellRoute 밖에 두면 하단 탭이 사라짐):
```dart
ShellRoute(
  builder: (context, state, child) => _MainShell(child: child),
  routes: [
    GoRoute(path: '/', builder: (_, __) => const ChatScreen()),
    GoRoute(path: '/tournaments', builder: (_, __) => const TournamentsScreen()),
    GoRoute(path: '/clubs', builder: (_, __) => const ClubsScreen()),
    if (!kIsWeb) GoRoute(path: '/speed-gun', builder: (_, __) => const SpeedGunScreen()),
    GoRoute(path: '/rules', builder: (_, __) => const RulesScreen()),
    GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
    GoRoute(path: '/admin', builder: (_, __) => const AdminScreen()),  // ← 추가
  ],
),
```

- [ ] **Step 2: flutter analyze + 앱 실행**

```bash
cd app && flutter analyze
```

```bash
make app
```

확인 사항:
- 앱 첫 진입 → 채팅 화면
- admin 계정 로그인 → 어드민 탭 표시
- 일반 계정 로그인 → 어드민 탭 미표시
- 채팅 빠른 명령어 칩 탭 → 즉시 전송
- 대회 탭 상단 → 내 등급 추천 대회 가로 스크롤
- 어드민 탭 → 3탭 정상 표시

- [ ] **Step 3: 최종 커밋 + push**

```bash
git add app/lib/router.dart
git commit -m "feat: 채팅 메인화 + 어드민 패널 완성"
git push
```
