# 지식베이스 1단계 (룰북·지식 문서 관리) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 관리자가 챗봇 RAG가 쓰는 룰북·지식 문서(`rule_articles`)를 어드민 콘솔에서 CRUD하고, 임베딩 상태 확인 + 즉시 재계산할 수 있게 한다.

**Architecture:** 신규 마이그레이션 없음(기존 `rule_articles` + admin RLS + 무효화 트리거 활용). Flutter가 admin RLS로 직접 CRUD. 즉시 재계산은 `embed-pending` Edge에 admin 호출 경로를 열어 호출. 어드민에 "지식베이스" 탭을 신규 파일로 추가(기존 4탭 불변).

**Tech Stack:** Flutter(Riverpod, http, supabase_flutter, flutter_markdown), Deno Edge Functions, Supabase Postgres RLS.

설계 문서: `docs/superpowers/specs/2026-05-27-knowledge-base-rules-design.md`

---

## File Structure

- **Modify** `supabase/functions/embed-pending/index.ts` — 인증 `requireServiceRole`→`requireServiceRoleOrAdmin` (admin 즉시 호출 허용). 원격 재배포.
- **Modify** `app/lib/models/tournament.dart` — `RuleArticle`에 `orderIdx`/`published`/`embeddingUpdatedAt`/`updatedAt` 추가 (fromJson 호환 유지).
- **Modify** `app/lib/services/api.dart` — `adminListRules`/`createRule`/`updateRule`/`deleteRule`/`nextRuleOrderIdx`/`recomputeRuleEmbedding`.
- **Modify** `app/lib/state/providers.dart` — `adminRulesProvider`.
- **Create** `app/lib/screens/admin/rule_edit_screen.dart` — 전체화면 편집(마크다운 토글/자동완성/재계산/삭제).
- **Create** `app/lib/screens/admin/knowledge_base_tab.dart` — 목록 탭(필터/상태뱃지/FAB).
- **Modify** `app/lib/screens/admin/admin_screen.dart` — 탭 1개 추가(최소 침습).
- **Test** `app/test/rule_article_test.dart` — RuleArticle 직렬화.

---

## Task 1: embed-pending에 admin 호출 허용

**Files:**
- Modify: `supabase/functions/embed-pending/index.ts`

- [ ] **Step 1: 인증 import·호출 교체**

파일 상단 import에서 `requireServiceRole`을 `requireServiceRoleOrAdmin`으로 바꾸고, 본문의 인증 호출도 교체한다. 현재(1행, 그리고 `Deno.serve` 내부 인증 라인):
```typescript
import { requireServiceRole } from '../_shared/auth.ts';
```
→
```typescript
import { requireServiceRoleOrAdmin } from '../_shared/auth.ts';
```
그리고 본문에서 `requireServiceRole(req)` 호출부를 찾아(보통 `const auth = requireServiceRole(req); if ('error' in auth) return auth.error;` 형태) `await requireServiceRoleOrAdmin(req)`로 교체:
```typescript
  const auth = await requireServiceRoleOrAdmin(req);
  if ('error' in auth) return auth.error;
```
(`requireServiceRoleOrAdmin`은 Promise를 반환하므로 `await` 필수. cron secret/service_role/admin 순으로 허용한다 — `_shared/auth.ts`에 이미 정의됨.)

- [ ] **Step 2: 정적 검증**

Run:
```bash
cd supabase/functions && deno check embed-pending/index.ts && deno lint embed-pending/
```
Expected: 에러·경고 없음.

- [ ] **Step 3: 커밋**

```bash
git add supabase/functions/embed-pending/index.ts
git commit -m "feat(embed): embed-pending에 admin 호출 허용 (지식베이스 즉시 재계산용)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 4: 원격 재배포 (controller가 MCP로 수행)**

`get_edge_function(embed-pending)`로 현재 배포 파일들을 받아 `index.ts`만 위 수정본으로 교체 후 `deploy_edge_function`(verify_jwt 기존값 false 유지)로 재배포. 또는 인증된 `supabase functions deploy embed-pending`.
Expected: version 증가. 비-admin 호출은 403.

---

## Task 2: RuleArticle 모델 확장 (TDD)

**Files:**
- Modify: `app/lib/models/tournament.dart:227-249`
- Test: `app/test/rule_article_test.dart`

- [ ] **Step 1: 실패 테스트 작성**

`app/test/rule_article_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/models/tournament.dart';

void main() {
  test('RuleArticle.fromJson parses new admin fields', () {
    final r = RuleArticle.fromJson({
      'id': 'r1',
      'sport': 'tennis',
      'category': '서브',
      'title': '서브 규칙',
      'body': '## 서브\n본문',
      'order_idx': 3,
      'published': false,
      'embedding_updated_at': '2026-05-27T00:00:00Z',
      'updated_at': '2026-05-27T01:00:00Z',
    });
    expect(r.orderIdx, 3);
    expect(r.published, false);
    expect(r.embeddingPending, false);
  });

  test('RuleArticle.fromJson stays compatible with legacy rows (no new fields)', () {
    final r = RuleArticle.fromJson({
      'id': 'r2', 'sport': 'futsal', 'category': '파울',
      'title': 't', 'body': 'b',
    });
    expect(r.orderIdx, 0);
    expect(r.published, true);
    expect(r.embeddingPending, true); // embedding_updated_at 없음 → 대기
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd app && flutter test test/rule_article_test.dart`
Expected: FAIL — `orderIdx`/`published`/`embeddingPending` 미정의.

- [ ] **Step 3: 모델 확장**

`app/lib/models/tournament.dart`의 `RuleArticle` 클래스(227-249)를 교체:
```dart
class RuleArticle {
  final String id;
  final String sport;
  final String category;
  final String title;
  final String body;
  final int orderIdx;
  final bool published;
  final DateTime? embeddingUpdatedAt;
  final DateTime? updatedAt;

  RuleArticle({
    required this.id,
    required this.sport,
    required this.category,
    required this.title,
    required this.body,
    this.orderIdx = 0,
    this.published = true,
    this.embeddingUpdatedAt,
    this.updatedAt,
  });

  /// embedding_updated_at 이 null 이면 임베딩 대기(재계산 필요), 아니면 최신.
  bool get embeddingPending => embeddingUpdatedAt == null;

  factory RuleArticle.fromJson(Map<String, dynamic> j) => RuleArticle(
        id: j['id'] as String,
        sport: j['sport'] as String,
        category: j['category'] as String,
        title: j['title'] as String,
        body: j['body'] as String,
        orderIdx: (j['order_idx'] as int?) ?? 0,
        published: (j['published'] as bool?) ?? true,
        embeddingUpdatedAt: j['embedding_updated_at'] != null
            ? DateTime.parse(j['embedding_updated_at'] as String)
            : null,
        updatedAt: j['updated_at'] != null
            ? DateTime.parse(j['updated_at'] as String)
            : null,
      );
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd app && flutter test test/rule_article_test.dart`
Expected: PASS (2 tests). 기존 `listRules`/`rules_screen` 호환(추가 필드 기본값).

- [ ] **Step 5: 커밋**

```bash
git add app/lib/models/tournament.dart app/test/rule_article_test.dart
git commit -m "feat(kb): RuleArticle 모델 확장 (orderIdx/published/embedding 상태)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: API — 룰 admin CRUD + 재계산

**Files:**
- Modify: `app/lib/services/api.dart` (rules 섹션, 현재 `listRules`가 있는 312행 부근)

- [ ] **Step 1: 메서드 추가**

`listRules`(312-320) 바로 아래에 추가:
```dart
  /// 관리자용: published 무관 전체 룰. embedding vector 는 제외(무거움).
  Future<List<RuleArticle>> adminListRules({String? sport}) async {
    var q = _supabase.from('rule_articles').select(
      'id, sport, category, title, body, order_idx, published, embedding_updated_at, updated_at',
    );
    if (sport != null) q = q.eq('sport', sport);
    final rows = await q
        .order('sport')
        .order('category')
        .order('order_idx');
    return (rows as List)
        .map((r) => RuleArticle.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> createRule(Map<String, dynamic> data) async {
    await _supabase.from('rule_articles').insert(data);
  }

  Future<void> updateRule(String id, Map<String, dynamic> data) async {
    await _supabase.from('rule_articles').update(data).eq('id', id);
  }

  Future<void> deleteRule(String id) async {
    await _supabase.from('rule_articles').delete().eq('id', id);
  }

  /// (sport, category) 내 다음 order_idx (max+1).
  Future<int> nextRuleOrderIdx(String sport, String category) async {
    final rows = await _supabase
        .from('rule_articles')
        .select('order_idx')
        .eq('sport', sport)
        .eq('category', category)
        .order('order_idx', ascending: false)
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return 0;
    return ((list.first['order_idx'] as int?) ?? 0) + 1;
  }

  /// 즉시 재임베딩: embedding 무효화 후 embed-pending 호출.
  Future<void> recomputeRuleEmbedding(String id) async {
    await _supabase
        .from('rule_articles')
        .update({'embedding': null, 'embedding_updated_at': null})
        .eq('id', id);
    final res = await http.post(
      _uri('embed-pending'),
      headers: await _authHeaders(),
    );
    _check(res);
  }
```

- [ ] **Step 2: 정적 검증**

Run: `cd app && flutter analyze lib/services/api.dart`
Expected: No issues. (`_supabase`/`_uri`/`_authHeaders`/`_check`/`http`/`RuleArticle` 모두 기존 존재.)
주의: PostgREST 빌더 `var q = ...select(...)` 후 `q = q.eq(...)` 재할당이 타입 오류면(`PostgrestTransformBuilder` vs `FilterBuilder`), `.eq`를 select 직후 체인으로 옮기고 sport는 분기 처리. 실제 오류 시 조정하고 보고.

- [ ] **Step 3: 커밋**

```bash
git add app/lib/services/api.dart
git commit -m "feat(kb): 룰 admin CRUD + 즉시 재임베딩 API

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Provider

**Files:**
- Modify: `app/lib/state/providers.dart` (파일 끝)

- [ ] **Step 1: provider 추가**

```dart
/// 관리자 룰 목록 (종목 필터, null=전체). 작업 후 invalidate 로 새로고침.
final adminRulesProvider =
    FutureProvider.autoDispose.family<List<RuleArticle>, String?>((ref, sport) {
  return ref.read(apiProvider).adminListRules(sport: sport);
});
```
(`RuleArticle`는 `models/tournament.dart`에서 이미 import됨 — 확인 후 없으면 추가.)

- [ ] **Step 2: 정적 검증**

Run: `cd app && flutter analyze lib/state/providers.dart`
Expected: No issues.

- [ ] **Step 3: 커밋**

```bash
git add app/lib/state/providers.dart
git commit -m "feat(kb): adminRulesProvider

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: 룰 편집 전체화면

**Files:**
- Create: `app/lib/screens/admin/rule_edit_screen.dart`

- [ ] **Step 1: 화면 작성**

`null`이면 신규, `RuleArticle`이면 수정. 저장 후 `pop(true)`. `flutter_markdown`의 `MarkdownBody`는 `rules_screen.dart`에서 import 경로 `package:flutter_markdown/flutter_markdown.dart` 사용 중 — 동일하게 사용.
```dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/tournament.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart';

class RuleEditScreen extends ConsumerStatefulWidget {
  final RuleArticle? rule; // null = 신규
  final List<String> existingCategories; // 자동완성 제안
  const RuleEditScreen({super.key, this.rule, this.existingCategories = const []});

  @override
  ConsumerState<RuleEditScreen> createState() => _RuleEditScreenState();
}

class _RuleEditScreenState extends ConsumerState<RuleEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late String _sport = widget.rule?.sport ?? 'tennis';
  late final _category = TextEditingController(text: widget.rule?.category ?? '');
  late final _title = TextEditingController(text: widget.rule?.title ?? '');
  late final _body = TextEditingController(text: widget.rule?.body ?? '');
  late final _orderIdx =
      TextEditingController(text: (widget.rule?.orderIdx ?? 0).toString());
  late bool _published = widget.rule?.published ?? true;
  bool _preview = false;
  bool _saving = false;

  bool get _isNew => widget.rule == null;

  @override
  void dispose() {
    _category.dispose();
    _title.dispose();
    _body.dispose();
    _orderIdx.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final api = ref.read(apiProvider);
    try {
      final data = {
        'sport': _sport,
        'category': _category.text.trim(),
        'title': _title.text.trim(),
        'body': _body.text,
        'order_idx': int.tryParse(_orderIdx.text.trim()) ?? 0,
        'published': _published,
      };
      if (_isNew) {
        await api.createRule(data);
      } else {
        await api.updateRule(widget.rule!.id, data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('저장 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _recompute() async {
    if (_isNew) return;
    try {
      await ref.read(apiProvider).recomputeRuleEmbedding(widget.rule!.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('재임베딩 요청 완료')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('재계산 실패: $e')));
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('문서 삭제'),
        content: const Text(
          '영구 삭제됩니다. 보통은 삭제 대신 "게시" 토글을 끄세요.\n정말 삭제할까요?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiProvider).deleteRule(widget.rule!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? '문서 작성' : '문서 수정'),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: '재임베딩',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _recompute,
            ),
          if (!_isNew)
            IconButton(
              tooltip: '삭제',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            // 종목 (admin 자유 선택)
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'tennis', label: Text(sportLabelFromString('tennis'))),
                ButtonSegment(value: 'futsal', label: Text(sportLabelFromString('futsal'))),
              ],
              selected: {_sport},
              onSelectionChanged: (s) => setState(() => _sport = s.first),
            ),
            const SizedBox(height: AppSpacing.md),
            // 카테고리 자동완성
            Autocomplete<String>(
              initialValue: TextEditingValue(text: _category.text),
              optionsBuilder: (v) {
                if (v.text.isEmpty) return widget.existingCategories;
                return widget.existingCategories
                    .where((c) => c.contains(v.text));
              },
              onSelected: (s) => _category.text = s,
              fieldViewBuilder: (context, controller, focus, _) {
                controller.text = _category.text;
                return TextFormField(
                  controller: controller,
                  focusNode: focus,
                  decoration: const InputDecoration(labelText: '카테고리 *'),
                  validator: (val) =>
                      (val == null || val.trim().isEmpty) ? '카테고리 필수' : null,
                  onChanged: (val) => _category.text = val,
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: '제목 *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '제목 필수' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _orderIdx,
              decoration: const InputDecoration(labelText: '표시 순서 (숫자)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: AppSpacing.md),
            SwitchListTile(
              title: const Text('게시'),
              value: _published,
              onChanged: (v) => setState(() => _published = v),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: AppSpacing.md),
            // 본문 편집 / 미리보기 토글
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('편집')),
                ButtonSegment(value: true, label: Text('미리보기')),
              ],
              selected: {_preview},
              onSelectionChanged: (s) => setState(() => _preview = s.first),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_preview)
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 200),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: AppRadius.card,
                ),
                child: MarkdownBody(data: '# ${_title.text}\n\n${_body.text}'),
              )
            else
              TextFormField(
                controller: _body,
                decoration: const InputDecoration(
                  labelText: '본문 (마크다운)',
                  alignLabelWithHint: true,
                ),
                maxLines: 14,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '본문 필수' : null,
              ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('저장'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 정적 검증**

Run: `cd app && flutter analyze lib/screens/admin/rule_edit_screen.dart`
Expected: No issues. (`AppSpacing`/`AppRadius`/`sportLabelFromString`/`MarkdownBody` 존재 확인됨.)

- [ ] **Step 3: 커밋**

```bash
git add app/lib/screens/admin/rule_edit_screen.dart
git commit -m "feat(kb): 룰 편집 전체화면 (마크다운 미리보기/자동완성/재계산/삭제)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: 지식베이스 목록 탭

**Files:**
- Create: `app/lib/screens/admin/knowledge_base_tab.dart`

- [ ] **Step 1: 위젯 작성**

자체 `Scaffold`(FAB 포함)를 반환해 admin TabBarView에 임베드한다. 종목 필터 + 임베딩 상태 뱃지.
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/tournament.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart';
import 'rule_edit_screen.dart';

class KnowledgeBaseTab extends ConsumerStatefulWidget {
  const KnowledgeBaseTab({super.key});

  @override
  ConsumerState<KnowledgeBaseTab> createState() => _KnowledgeBaseTabState();
}

class _KnowledgeBaseTabState extends ConsumerState<KnowledgeBaseTab> {
  String? _sportFilter; // null=전체

  Future<void> _openEditor(List<RuleArticle> all, {RuleArticle? rule}) async {
    final cats = all.map((r) => r.category).toSet().toList()..sort();
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RuleEditScreen(rule: rule, existingCategories: cats),
      ),
    );
    if (changed == true) ref.invalidate(adminRulesProvider(_sportFilter));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rulesAsync = ref.watch(adminRulesProvider(_sportFilter));

    return Scaffold(
      body: Column(
        children: [
          // 종목 필터
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: SegmentedButton<String?>(
              segments: [
                const ButtonSegment(value: null, label: Text('전체')),
                ButtonSegment(value: 'tennis', label: Text(sportLabelFromString('tennis'))),
                ButtonSegment(value: 'futsal', label: Text(sportLabelFromString('futsal'))),
              ],
              selected: {_sportFilter},
              onSelectionChanged: (s) => setState(() => _sportFilter = s.first),
            ),
          ),
          Expanded(
            child: rulesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('로드 실패: $e')),
              data: (rules) => rules.isEmpty
                  ? const Center(child: Text('문서가 없습니다'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg),
                      itemCount: rules.length,
                      itemBuilder: (_, i) {
                        final r = rules[i];
                        return Card(
                          child: ListTile(
                            title: Text(r.title),
                            subtitle: Text(
                                '${sportLabelFromString(r.sport)} · ${r.category} · #${r.orderIdx}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!r.published)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        right: AppSpacing.sm),
                                    child: Text('미게시',
                                        style: TextStyle(
                                            color: cs.onSurfaceVariant)),
                                  ),
                                _EmbeddingBadge(pending: r.embeddingPending),
                              ],
                            ),
                            onTap: () => _openEditor(rules, rule: r),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: rulesAsync.maybeWhen(
        data: (rules) => FloatingActionButton.extended(
          onPressed: () => _openEditor(rules),
          icon: const Icon(Icons.add_rounded),
          label: const Text('문서 작성'),
        ),
        orElse: () => null,
      ),
    );
  }
}

class _EmbeddingBadge extends StatelessWidget {
  final bool pending;
  const _EmbeddingBadge({required this.pending});

  @override
  Widget build(BuildContext context) {
    final color = pending ? Colors.orange : Colors.green;
    final label = pending ? '임베딩 대기' : '최신';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}
```

- [ ] **Step 2: 정적 검증**

Run: `cd app && flutter analyze lib/screens/admin/knowledge_base_tab.dart`
Expected: No issues.

- [ ] **Step 3: 커밋**

```bash
git add app/lib/screens/admin/knowledge_base_tab.dart
git commit -m "feat(kb): 지식베이스 목록 탭 (필터/임베딩 상태 뱃지/FAB)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: admin_screen에 탭 추가 (최소 침습)

**Files:**
- Modify: `app/lib/screens/admin/admin_screen.dart` (46행 TabController, 586-606 TabBar/View, import)

- [ ] **Step 1: import 추가**

상단 import 블록에:
```dart
import 'knowledge_base_tab.dart';
```

- [ ] **Step 2: TabController length 4→5**

46행 `_tab = TabController(length: 4, vsync: this);` →
```dart
    _tab = TabController(length: 5, vsync: this);
```

- [ ] **Step 3: Tab + TabBarView child 추가**

590-595 `tabs: const [...]`의 마지막 `Tab(text: '클럽 승인'),` 뒤에 추가:
```dart
            Tab(text: '지식베이스'),
```
600-605 `children: [...]`의 마지막 `_buildPendingClubsTab(),` 뒤에 추가:
```dart
          const KnowledgeBaseTab(),
```
(지식베이스 FAB는 `KnowledgeBaseTab` 내부 Scaffold가 담당하므로 admin_screen의 `floatingActionButton: _tab.index == 2 ? ...` 분기는 수정 불필요 — 인덱스 4에선 admin FAB가 null이고 내부 FAB가 표시됨.)

- [ ] **Step 4: 정적 검증**

Run: `cd app && flutter analyze lib/screens/admin/admin_screen.dart`
Expected: No issues.

- [ ] **Step 5: 커밋**

```bash
git add app/lib/screens/admin/admin_screen.dart
git commit -m "feat(kb): 어드민에 지식베이스 탭 추가

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: 전체 검증

**Files:** 없음 (검증)

- [ ] **Step 1: 정적 + 단위**

Run:
```bash
cd app && flutter analyze && flutter test
cd ../supabase/functions && deno check embed-pending/index.ts
```
Expected: analyze No issues, 전체 test PASS, deno check 통과.

- [ ] **Step 2: admin 계정 E2E (앱 hot restart 후)**

1. 어드민 → "지식베이스" 탭 → "문서 작성" → tennis/카테고리/제목/본문 입력, 미리보기 토글 확인 → 저장
2. 목록에 노출, 뱃지 "임베딩 대기"
3. 문서 열어 "재임베딩"(새로고침 아이콘) → 잠시 후 목록 새로고침 시 "최신"
   - 확인(controller): 원격 `select id, embedding_updated_at from rule_articles where title=...` — null→not null
4. 본문 수정 저장 → 다시 "임베딩 대기"로 (트리거)
5. 게시 토글 off → 앱 `rules_screen`에서 해당 룰 사라짐
6. 문서 열어 삭제(확인 다이얼로그) → 목록에서 제거

- [ ] **Step 3: 권한 검증 (controller, MCP execute_sql)**

비-admin 컨텍스트에서 `rule_articles` insert가 RLS로 거부되는지:
```sql
set local role authenticated;
set local request.jwt.claims = '{"sub":"<non-admin-user-uuid>","role":"authenticated"}';
insert into rule_articles (sport, category, title, body) values ('tennis','t','t','b'); -- 실패해야 정상
```
Expected: RLS 위반으로 실패.

---

## Self-Review 결과

- **Spec 커버리지**: 목록(T6) · CRUD(T3,5) · 게시토글(T5) · 임베딩 상태 뱃지(T2,6) · 즉시 재계산(T1,3,5) · 카테고리 자동완성(T5) · order_idx 숫자(T5) · 종목 자유(T5) · 탭 신규 분리(T6,7) · embed-pending admin(T1) — 전부 태스크 존재.
- **Placeholder**: 없음. 모든 코드 스텝에 전체 코드.
- **타입 일관성**: `RuleArticle.{orderIdx,published,embeddingUpdatedAt,embeddingPending}`(T2) ↔ 사용처(T5,6) 일치. API `adminListRules/createRule/updateRule/deleteRule/nextRuleOrderIdx/recomputeRuleEmbedding`(T3) ↔ 화면 호출(T5,6) 일치. `adminRulesProvider(String?)`(T4) ↔ watch/invalidate(T6) 일치.
- **주의**: embed-pending 본문의 실제 `requireServiceRole` 호출 형태는 구현 시 파일 확인 후 정확히 교체. PostgREST 빌더 재할당 타입 이슈 시 T3 Step2 지침대로 조정.
