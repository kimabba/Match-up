import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_card.dart';

class TournamentSubmitScreen extends ConsumerStatefulWidget {
  const TournamentSubmitScreen({super.key});

  @override
  ConsumerState<TournamentSubmitScreen> createState() =>
      _TournamentSubmitScreenState();
}

class _TournamentSubmitScreenState
    extends ConsumerState<TournamentSubmitScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _organizer = TextEditingController();
  final _region = TextEditingController();
  final _location = TextEditingController();
  final _description = TextEditingController();
  final _sourceUrl = TextEditingController();
  Sport _sport = Sport.tennis;
  DateTime? _startDate;
  final Set<String> _grades = {};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _organizer.dispose();
    _region.dispose();
    _location.dispose();
    _description.dispose();
    _sourceUrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDate: _startDate ?? now,
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_startDate == null) {
      setState(() => _error = '시작일을 선택하세요');
      return;
    }
    if (_grades.isEmpty) {
      setState(() => _error = '출전 가능 등급을 1개 이상 선택하세요');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).submitTournament({
        'sport': sportToString(_sport),
        'title': _title.text.trim(),
        if (_organizer.text.trim().isNotEmpty) 'organizer': _organizer.text.trim(),
        if (_description.text.trim().isNotEmpty)
          'description': _description.text.trim(),
        'start_date': _startDate!.toIso8601String().substring(0, 10),
        if (_region.text.trim().isNotEmpty) 'region': _region.text.trim(),
        if (_location.text.trim().isNotEmpty) 'location': _location.text.trim(),
        'eligible_grades': _grades.toList(),
        if (_sourceUrl.text.trim().isNotEmpty) 'source_url': _sourceUrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('제보 완료. 관리자 승인 후 노출됩니다.')),
        );
        context.pop();
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final grades = gradesFor(_sport);

    return Scaffold(
      appBar: AppBar(title: const Text('대회 제보')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            AppCard(
              variant: AppCardVariant.outlined,
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '제보된 대회는 관리자 승인 후 모든 사용자에게 노출됩니다.',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // 종목 선택
            _Label('종목 *'),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<Sport>(
              segments: const [
                ButtonSegment(
                  value: Sport.tennis,
                  icon: Icon(Icons.sports_tennis_rounded),
                  label: Text('테니스'),
                ),
                ButtonSegment(
                  value: Sport.futsal,
                  icon: Icon(Icons.sports_soccer_rounded),
                  label: Text('풋살'),
                ),
              ],
              selected: {_sport},
              onSelectionChanged: (v) => setState(() {
                _sport = v.first;
                _grades.clear();
              }),
            ),
            const SizedBox(height: AppSpacing.lg),

            TextFormField(
              controller: _title,
              decoration: _inputDeco('대회명 *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '필수 항목입니다' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _organizer,
              decoration: _inputDeco('주최'),
            ),
            const SizedBox(height: AppSpacing.md),

            // 날짜 선택
            _Label('시작일 *'),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              onTap: _pickDate,
              variant: AppCardVariant.outlined,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded,
                      size: 18, color: cs.primary),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    _startDate == null
                        ? '날짜를 선택하세요'
                        : DateFormat('yyyy년 M월 d일 (E)', 'ko').format(_startDate!),
                    style: tt.bodyMedium?.copyWith(
                      color: _startDate == null ? cs.onSurfaceVariant : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            TextFormField(
              controller: _region,
              decoration: _inputDeco('지역 (시·도)'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _location,
              decoration: _inputDeco('상세 장소'),
            ),
            const SizedBox(height: AppSpacing.lg),

            // 등급 선택
            _Label('출전 가능 등급 *'),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final g in grades)
                  FilterChip(
                    label: Text(gradeLabel(g)),
                    selected: _grades.contains(g),
                    onSelected: (s) => setState(() {
                      s ? _grades.add(g) : _grades.remove(g);
                    }),
                    selectedColor: cs.primaryContainer,
                    checkmarkColor: cs.onPrimaryContainer,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            TextFormField(
              controller: _description,
              decoration: _inputDeco('대회 설명'),
              maxLines: 4,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _sourceUrl,
              decoration: _inputDeco('원본 공고 URL'),
              keyboardType: TextInputType.url,
            ),

            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              AppCard(
                variant: AppCardVariant.outlined,
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded, color: cs.error, size: 18),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _error!,
                        style: tt.bodySmall?.copyWith(color: cs.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            AppPrimaryButton(
              label: _busy ? '제보 중...' : '제보하기',
              onPressed: _busy ? null : _submit,
            ),
            const SizedBox(height: AppSpacing.xxxl),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String label) => InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: AppRadius.card),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
      );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
    );
  }
}
