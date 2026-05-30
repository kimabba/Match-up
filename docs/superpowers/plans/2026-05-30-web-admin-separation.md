# Web Admin / App User Separation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Flutter Web 빌드를 어드민 전용 대시보드로 분리하고, 모바일 앱은 일반 사용자 전용으로 유지한다.

**Architecture:** `router.dart`에서 `kIsWeb` 기준으로 라우트 트리를 분기. 웹은 `AdminShell`(사이드바+탑바), 앱은 기존 `_MainShell`(Bottom Nav). `notifications.dart`는 conditional import로 웹 빌드 차단 해제.

**Tech Stack:** Flutter (go_router, Riverpod), Supabase (PostgreSQL, Edge Functions), Deno

**Spec:** `docs/superpowers/specs/2026-05-30-web-admin-separation-design.md`

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `app/lib/services/notifications_web.dart` | FCM no-op stub (웹용, dart:io 없음) |
| `app/lib/screens/admin/admin_shell.dart` | 웹 어드민 레이아웃 (사이드바 + 탑바 + child) |
| `app/lib/screens/admin/no_access_screen.dart` | 비어드민 웹 접속 시 안내 화면 |
| `app/lib/screens/admin/tournament_edit_screen.dart` | 대회 수기 편집 화면 |
| `supabase/migrations/042_manual_description.sql` | `manual_description` boolean 컬럼 |

### Modified Files

| File | Change |
|------|--------|
| `app/lib/main.dart` | notifications conditional import |
| `app/lib/router.dart` | 웹/앱 라우트 분기, AdminShellRoute, /no-access |
| `app/lib/screens/admin/admin_screen.dart` | 탭 빌더 메서드를 public static 위젯으로 추출 |
| `supabase/functions/_shared/crawler.ts` | `upsertTournament`에서 `manual_description` 체크 |

---

### Task 1: Web Build Unblock — notifications stub

**Files:**
- Create: `app/lib/services/notifications_web.dart`
- Modify: `app/lib/main.dart:10`

- [ ] **Step 1: Create notifications_web.dart stub**

```dart
// app/lib/services/notifications_web.dart
// 웹 빌드용 no-op stub — dart:io / Firebase 미지원 플랫폼에서 사용

import 'api.dart';

/// 웹에서는 FCM 을 사용하지 않으므로 no-op.
Future<void> initNotifications(ApiService api) async {}
```

- [ ] **Step 2: Update main.dart conditional import**

`app/lib/main.dart` 10행을 변경:

```dart
// before:
import 'services/notifications.dart';

// after:
import 'services/notifications.dart'
    if (dart.library.html) 'services/notifications_web.dart';
```

- [ ] **Step 3: Verify web build compiles**

Run: `cd app && flutter build web --dart-define=SUPABASE_URL=https://bsjdgwmveokanclqwtvx.supabase.co --dart-define=SUPABASE_ANON_KEY=test 2>&1 | tail -5`
Expected: "Compiling lib/main.dart for the Web..." 성공 (또는 web-specific 에러만, dart:io 에러 없음)

- [ ] **Step 4: Verify mobile build still works**

Run: `cd app && flutter analyze`
Expected: No issues found

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/notifications_web.dart app/lib/main.dart
git commit -m "fix(web): notifications conditional import로 웹 빌드 차단 해제 (JY-21)"
```

---

### Task 2: NoAccessScreen — 비어드민 웹 접속 화면

**Files:**
- Create: `app/lib/screens/admin/no_access_screen.dart`

- [ ] **Step 1: Create NoAccessScreen**

```dart
// app/lib/screens/admin/no_access_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NoAccessScreen extends StatelessWidget {
  const NoAccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.admin_panel_settings_outlined, size: 64, color: cs.onSurfaceVariant),
            const SizedBox(height: 24),
            Text(
              '관리자 권한이 필요합니다',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '이 페이지는 관리자만 접근할 수 있습니다.\n모바일 앱을 설치하여 Match-up을 이용해주세요.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: () => Supabase.instance.client.auth.signOut(),
              icon: const Icon(Icons.logout),
              label: const Text('로그아웃'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/lib/screens/admin/no_access_screen.dart
git commit -m "feat(admin): 비어드민 웹 접속 안내 화면 추가"
```

---

### Task 3: AdminShell — 사이드바 + 탑바 레이아웃

**Files:**
- Create: `app/lib/screens/admin/admin_shell.dart`

- [ ] **Step 1: Create AdminShell widget**

```dart
// app/lib/screens/admin/admin_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../state/providers.dart';

class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.child});
  final Widget child;

  static const _items = [
    ('/admin', Icons.dashboard_outlined, '대시보드'),
    ('/admin/drafts', Icons.fact_check_outlined, 'Draft 승인'),
    ('/admin/sources', Icons.rss_feed_outlined, '크롤 소스'),
    ('/admin/clubs', Icons.groups_outlined, '클럽 승인'),
    ('/admin/kb', Icons.menu_book_outlined, '지식베이스'),
    ('/admin/tournaments', Icons.edit_note_outlined, '대회 편집'),
  ];

  int _selectedIndex(String location) {
    for (var i = _items.length - 1; i >= 0; i--) {
      if (location.startsWith(_items[i].$1)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);

    return isAdmin.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const Scaffold(
        body: Center(child: Text('권한 확인 실패')),
      ),
      data: (admin) {
        if (!admin) {
          // redirect가 처리하지만 혹시 렌더되면 빈 화면
          return const SizedBox.shrink();
        }

        final loc = GoRouterState.of(context).matchedLocation;
        final idx = _selectedIndex(loc);
        final cs = Theme.of(context).colorScheme;
        final user = ref.watch(currentUserProvider);

        return Scaffold(
          body: Row(
            children: [
              // 사이드바
              Container(
                width: 220,
                color: cs.surfaceContainerLow,
                child: Column(
                  children: [
                    // 헤더
                    Container(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.sports_tennis, color: cs.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Match-up',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // 메뉴 항목
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        children: [
                          for (var i = 0; i < _items.length; i++)
                            _SidebarItem(
                              icon: _items[i].$2,
                              label: _items[i].$3,
                              selected: i == idx,
                              onTap: () => context.go(_items[i].$1),
                            ),
                        ],
                      ),
                    ),
                    // 하단 유저 정보
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            child: Text(
                              (user?.email ?? '?')[0].toUpperCase(),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              user?.email ?? '',
                              style: Theme.of(context).textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.logout, size: 18),
                            tooltip: '로그아웃',
                            onPressed: () =>
                                Supabase.instance.client.auth.signOut(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 콘텐츠
              Expanded(child: child),
            ],
          ),
        );
      },
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected ? cs.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/lib/screens/admin/admin_shell.dart
git commit -m "feat(admin): AdminShell 사이드바+탑바 레이아웃"
```

---

### Task 4: Router Branching — 웹/앱 라우트 분기

**Files:**
- Modify: `app/lib/router.dart`

- [ ] **Step 1: Add imports and /no-access route**

`router.dart` 상단에 import 추가:

```dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'screens/admin/admin_shell.dart';
import 'screens/admin/no_access_screen.dart';
```

`knowledge_base_tab.dart` import는 이미 `admin_screen.dart`에서 처리되므로 불필요.

- [ ] **Step 2: Update redirect logic**

`router.dart`의 `redirect` 함수를 변경:

```dart
redirect: (context, state) async {
  final user = ref.read(currentUserProvider);
  final loc = state.matchedLocation;

  if (user == null) {
    return loc == '/login' ? null : '/login';
  }

  // 웹: onboarding skip, 어드민 가드
  if (kIsWeb) {
    if (loc == '/login') return '/admin';
    if (loc.startsWith('/admin')) {
      final isAdmin = ref.read(isAdminProvider).valueOrNull ?? false;
      if (!isAdmin) return '/no-access';
      return null;
    }
    // 웹에서 앱 경로 접근 시 어드민으로 redirect
    final isAdmin = ref.read(isAdminProvider).valueOrNull ?? false;
    return isAdmin ? '/admin' : '/no-access';
  }

  // 앱: 기존 로직
  final sportsAsync = ref.read(userSportsProvider);
  if (sportsAsync.isLoading) return null;
  final sports = sportsAsync.valueOrNull ?? const [];
  if (sports.isEmpty && loc != '/onboarding') return '/onboarding';

  if (loc.startsWith('/admin')) {
    final isAdmin = ref.read(isAdminProvider).valueOrNull ?? false;
    if (!isAdmin) return '/';
  }

  if (loc == '/login') return '/';
  return null;
},
```

- [ ] **Step 3: Move /admin out of ShellRoute, add AdminShellRoute**

기존 `ShellRoute.routes`에서 `/admin` 라우트 제거:

```dart
// 삭제: GoRoute(path: '/admin', builder: (_, __) => const AdminScreen()),
```

`routes` 리스트에 추가 (ShellRoute 뒤, 전역 라우트들 사이):

```dart
// 웹 전용
GoRoute(path: '/no-access', builder: (_, __) => const NoAccessScreen()),

// Admin routes (AdminShell wrapping)
ShellRoute(
  builder: (context, state, child) => AdminShell(child: child),
  routes: [
    GoRoute(path: '/admin', builder: (_, __) => const AdminScreen()),
    GoRoute(path: '/admin/drafts', builder: (_, __) => const AdminScreen(initialTab: 1)),
    GoRoute(path: '/admin/sources', builder: (_, __) => const AdminScreen(initialTab: 2)),
    GoRoute(path: '/admin/clubs', builder: (_, __) => const AdminScreen(initialTab: 3)),
    GoRoute(path: '/admin/kb', builder: (_, __) => const AdminScreen(initialTab: 4)),
    GoRoute(
      path: '/admin/edit/:id',
      builder: (_, state) => TournamentEditScreen(
        tournamentId: state.pathParameters['id']!,
      ),
    ),
  ],
),
```

Note: `AdminScreen`에 `initialTab` 파라미터 추가가 필요 (Task 5에서 처리).

- [ ] **Step 4: Remove /admin from _moreSubPaths**

```dart
// before:
static const _moreSubPaths = ['/more', '/speed-gun', '/rules', '/profile', '/admin'];

// after:
static const _moreSubPaths = ['/more', '/speed-gun', '/rules', '/profile'];
```

- [ ] **Step 5: Add TournamentEditScreen import**

```dart
import 'screens/admin/tournament_edit_screen.dart';
```

- [ ] **Step 6: Verify analyze passes**

Run: `cd app && flutter analyze`
Expected: No issues (TournamentEditScreen은 Task 7에서 생성하므로 placeholder import 필요시 주석 처리)

- [ ] **Step 7: Commit**

```bash
git add app/lib/router.dart
git commit -m "feat(router): 웹/앱 라우트 분기 + AdminShellRoute"
```

---

### Task 5: AdminScreen — initialTab 파라미터 추가

**Files:**
- Modify: `app/lib/screens/admin/admin_screen.dart:10-20`

- [ ] **Step 1: Add initialTab parameter**

```dart
// before:
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

// after:
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key, this.initialTab = 0});
  final int initialTab;
```

- [ ] **Step 2: Use initialTab in initState**

```dart
// before:
_tab = TabController(length: 5, vsync: this);

// after:
_tab = TabController(length: 5, vsync: this, initialIndex: widget.initialTab);
```

- [ ] **Step 3: Verify analyze**

Run: `cd app && flutter analyze`
Expected: No issues

- [ ] **Step 4: Commit**

```bash
git add app/lib/screens/admin/admin_screen.dart
git commit -m "feat(admin): AdminScreen initialTab 파라미터 추가"
```

---

### Task 6: DB Migration — manual_description 컬럼

**Files:**
- Create: `supabase/migrations/042_manual_description.sql`

- [ ] **Step 1: Create migration**

```sql
-- 042: 수동 편집 description 보호 플래그
-- 크롤러가 수동 편집한 description을 덮어쓰지 않도록 한다.
ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS manual_description boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.tournaments.manual_description IS
  'true이면 크롤러가 description을 덮어쓰지 않음. 어드민 수기 편집 시 자동 설정.';
```

- [ ] **Step 2: Apply migration remotely**

Run: `supabase db push --project-ref bsjdgwmveokanclqwtvx` 또는 SQL Editor에서 직접 실행.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/042_manual_description.sql
git commit -m "migration(042): manual_description 컬럼 추가"
```

---

### Task 7: Backend — upsertTournament manual_description 체크

**Files:**
- Modify: `supabase/functions/_shared/crawler.ts:72-85`

- [ ] **Step 1: Update select to include manual_description**

```typescript
// before:
.select('id, title, start_date, application_deadline, eligible_grades, region')

// after:
.select('id, title, start_date, application_deadline, eligible_grades, region, manual_description')
```

- [ ] **Step 2: Update description overwrite logic**

```typescript
// before:
if (t.description !== undefined) updatePayload.description = t.description ?? null;

// after:
if (t.description !== undefined && !existing.manual_description) {
  updatePayload.description = t.description ?? null;
}
```

- [ ] **Step 3: Verify deno fmt and lint**

Run: `deno fmt --check supabase/functions/_shared/crawler.ts && deno lint supabase/functions/_shared/crawler.ts`
Expected: No issues

- [ ] **Step 4: Deploy crawl-dispatch**

```bash
supabase functions deploy crawl-dispatch --no-verify-jwt --project-ref bsjdgwmveokanclqwtvx --import-map=supabase/functions/deno.json
```

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/crawler.ts
git commit -m "fix(crawler): manual_description 플래그로 수동 편집 보호"
```

---

### Task 8: TournamentEditScreen — 대회 수기 편집 화면

**Files:**
- Create: `app/lib/screens/admin/tournament_edit_screen.dart`

- [ ] **Step 1: Create TournamentEditScreen**

화면 구성:
- `tournamentId`를 받아 Supabase에서 대회 데이터 로드
- 편집 가능 필드: description, location, application_deadline, status (draft/published)
- 저장 버튼: `supabase.from('tournaments').update({...}).eq('id', id)`
- 저장 시 `manual_description = true` 자동 설정 (description 변경 시)
- 401 응답 시 로그아웃 처리
- 성공 시 SnackBar + 목록으로 돌아가기

```dart
// app/lib/screens/admin/tournament_edit_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../state/providers.dart';

class TournamentEditScreen extends ConsumerStatefulWidget {
  const TournamentEditScreen({super.key, required this.tournamentId});
  final String tournamentId;

  @override
  ConsumerState<TournamentEditScreen> createState() => _TournamentEditScreenState();
}

class _TournamentEditScreenState extends ConsumerState<TournamentEditScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic>? _data;

  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _location;
  late final TextEditingController _deadline;
  String _status = 'draft';

  @override
  void initState() {
    super.initState();
    _title = TextEditingController();
    _description = TextEditingController();
    _location = TextEditingController();
    _deadline = TextEditingController();
    _loadTournament();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _location.dispose();
    _deadline.dispose();
    super.dispose();
  }

  Future<void> _loadTournament() async {
    try {
      final supabase = ref.read(supabaseProvider);
      final row = await supabase
          .from('tournaments')
          .select()
          .eq('id', widget.tournamentId)
          .single();
      if (mounted) {
        setState(() {
          _data = row;
          _title.text = row['title'] ?? '';
          _description.text = row['description'] ?? '';
          _location.text = row['location'] ?? '';
          _deadline.text = row['application_deadline'] ?? '';
          _status = row['status'] ?? 'draft';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로드 실패: $e')),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      final supabase = ref.read(supabaseProvider);
      final descChanged = _description.text != (_data?['description'] ?? '');
      await supabase.from('tournaments').update({
        'title': _title.text.trim(),
        'description': _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        'location': _location.text.trim().isEmpty
            ? null
            : _location.text.trim(),
        'application_deadline': _deadline.text.trim().isEmpty
            ? null
            : _deadline.text.trim(),
        'status': _status,
        if (descChanged) 'manual_description': true,
      }).eq('id', widget.tournamentId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장 완료')),
        );
        context.go('/admin/drafts');
      }
    } on AuthException {
      if (mounted) {
        await Supabase.instance.client.auth.signOut();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_data == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('대회 편집')),
        body: const Center(child: Text('대회를 찾을 수 없습니다')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('대회 편집'),
        actions: [
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: const Text('저장'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 메타 정보 (읽기 전용)
                Text(
                  '${_data!['sport']} · ${_data!['region'] ?? ''} · ${_data!['start_date']}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_data!['source_url'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _data!['source_url'],
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 24),
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: '대회명'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '필수' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _description,
                  decoration: const InputDecoration(
                    labelText: '설명',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 5,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _location,
                  decoration: const InputDecoration(labelText: '장소'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _deadline,
                  decoration: const InputDecoration(
                    labelText: '신청 마감일 (YYYY-MM-DD)',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _status,
                  decoration: const InputDecoration(labelText: '상태'),
                  items: const [
                    DropdownMenuItem(value: 'draft', child: Text('Draft')),
                    DropdownMenuItem(value: 'published', child: Text('Published')),
                    DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? 'draft'),
                ),
                const SizedBox(height: 16),
                // eligible_grades (읽기 전용 표시)
                if (_data!['eligible_grades'] != null)
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final g in (_data!['eligible_grades'] as List))
                        Chip(label: Text(g.toString(), style: const TextStyle(fontSize: 12))),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify analyze**

Run: `cd app && flutter analyze`
Expected: No issues

- [ ] **Step 3: Commit**

```bash
git add app/lib/screens/admin/tournament_edit_screen.dart
git commit -m "feat(admin): 대회 수기 편집 화면 (TournamentEditScreen)"
```

---

### Task 9: Final Wiring — router에 TournamentEditScreen import 연결

**Files:**
- Modify: `app/lib/router.dart`

- [ ] **Step 1: Ensure all imports are present and routes compile**

`router.dart` 상단의 import가 모두 있는지 확인:

```dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'screens/admin/admin_shell.dart';
import 'screens/admin/no_access_screen.dart';
import 'screens/admin/tournament_edit_screen.dart';
```

- [ ] **Step 2: Add /admin/tournaments list route**

AdminShellRoute에 대회 목록 라우트 추가 (편집할 대회를 선택하는 화면).
기존 `TournamentsScreen`을 재사용하되, 웹에서는 각 대회에 "편집" 버튼이 필요.
MVP에서는 간단히 전체 대회 목록을 표시하고 tap 시 편집 화면으로 이동:

```dart
GoRoute(
  path: '/admin/tournaments',
  builder: (_, __) => const _AdminTournamentListScreen(),
),
```

`_AdminTournamentListScreen`은 `router.dart` 하단에 private 위젯으로 추가:

```dart
class _AdminTournamentListScreen extends ConsumerWidget {
  const _AdminTournamentListScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supabase = ref.read(supabaseProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('대회 편집')),
      body: FutureBuilder(
        future: supabase
            .from('tournaments')
            .select('id, title, sport, region, start_date, status')
            .order('start_date', ascending: false)
            .limit(100),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data as List;
          if (rows.isEmpty) {
            return const Center(child: Text('대회 없음'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (_, i) {
              final r = rows[i];
              final statusColor = r['status'] == 'published'
                  ? Colors.green
                  : (r['status'] == 'draft' ? Colors.orange : Colors.grey);
              return ListTile(
                title: Text(r['title'] ?? ''),
                subtitle: Text(
                  '${r['sport']} · ${r['region'] ?? ''} · ${r['start_date']}',
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(r['status'] ?? '', style: TextStyle(color: statusColor, fontSize: 12)),
                ),
                onTap: () => context.go('/admin/edit/${r['id']}'),
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 3: Full analyze + web build test**

Run: `cd app && flutter analyze && flutter build web --dart-define=SUPABASE_URL=https://bsjdgwmveokanclqwtvx.supabase.co --dart-define=SUPABASE_ANON_KEY=test 2>&1 | tail -5`
Expected: analyze clean, web build success

- [ ] **Step 4: Commit**

```bash
git add app/lib/router.dart
git commit -m "feat(admin): 라우터 최종 연결 + 대회 목록 화면"
```

---

### Task 10: Verification

- [ ] **Step 1: flutter analyze**

Run: `cd app && flutter analyze`
Expected: No issues found

- [ ] **Step 2: flutter build web**

Run: `cd app && flutter build web --dart-define=SUPABASE_URL=https://bsjdgwmveokanclqwtvx.supabase.co --dart-define=SUPABASE_ANON_KEY=<실제키>`
Expected: Build success

- [ ] **Step 3: Verify DB migration applied**

```sql
SELECT column_name FROM information_schema.columns
WHERE table_name = 'tournaments' AND column_name = 'manual_description';
```
Expected: 1 row

- [ ] **Step 4: Push all commits**

```bash
git push origin main
```
