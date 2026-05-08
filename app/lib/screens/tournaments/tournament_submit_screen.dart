import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../state/providers.dart';
import '../../utils/grade_labels.dart';

class TournamentSubmitScreen extends ConsumerStatefulWidget {
  const TournamentSubmitScreen({super.key});

  @override
  ConsumerState<TournamentSubmitScreen> createState() => _TournamentSubmitScreenState();
}

class _TournamentSubmitScreenState extends ConsumerState<TournamentSubmitScreen> {
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
        if (_description.text.trim().isNotEmpty) 'description': _description.text.trim(),
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
    final grades = gradesFor(_sport);
    return Scaffold(
      appBar: AppBar(title: const Text('대회 제보')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('제보된 대회는 관리자 승인 후 모든 사용자에게 노출됩니다.',
                style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 12),
            SegmentedButton<Sport>(
              segments: const [
                ButtonSegment(value: Sport.tennis, label: Text('테니스')),
                ButtonSegment(value: Sport.futsal, label: Text('풋살')),
              ],
              selected: {_sport},
              onSelectionChanged: (v) => setState(() {
                _sport = v.first;
                _grades.clear();
              }),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: '대회명 *', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? '필수' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _organizer,
              decoration: const InputDecoration(labelText: '주최', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            ListTile(
              tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              title: Text(_startDate == null
                  ? '시작일 선택 *'
                  : DateFormat('yyyy-MM-dd').format(_startDate!)),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickDate,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _region,
              decoration:
                  const InputDecoration(labelText: '지역(시도)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _location,
              decoration: const InputDecoration(labelText: '상세 장소', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            const Text('출전 가능 등급 *', style: TextStyle(fontWeight: FontWeight.bold)),
            Wrap(
              spacing: 8,
              children: [
                for (final g in grades)
                  FilterChip(
                    label: Text(gradeLabel(g)),
                    selected: _grades.contains(g),
                    onSelected: (s) => setState(() {
                      s ? _grades.add(g) : _grades.remove(g);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(labelText: '설명', border: OutlineInputBorder()),
              maxLines: 4,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _sourceUrl,
              decoration: const InputDecoration(labelText: '원본 공고 URL', border: OutlineInputBorder()),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: const Text('제보하기'),
            ),
          ],
        ),
      ),
    );
  }
}
