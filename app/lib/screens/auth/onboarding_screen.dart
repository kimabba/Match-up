import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/tournament.dart';
import '../../state/providers.dart';
import '../../utils/grade_labels.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final Map<Sport, String?> _selected = {Sport.tennis: null, Sport.futsal: null};
  Sport _primary = Sport.tennis;
  bool _busy = false;
  String? _error;

  bool get _canSubmit =>
      _selected.values.any((v) => v != null) &&
      _selected[_primary] != null;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider);
      final list = <UserSport>[];
      for (final sport in Sport.values) {
        final grade = _selected[sport];
        if (grade == null) continue;
        list.add(UserSport(
          sport: sportToString(sport),
          grade: grade,
          isPrimary: sport == _primary,
        ));
      }
      await api.saveUserSports(list);
      ref.invalidate(userSportsProvider);
      if (mounted) context.go('/');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _sportSection(Sport sport) {
    final grades = gradesFor(sport);
    final selected = _selected[sport];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(sportLabel(sport),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (selected != null)
                  Row(children: [
                    // ignore: deprecated_member_use
                    Radio<Sport>(
                      value: sport,
                      // ignore: deprecated_member_use
                      groupValue: _primary,
                      // ignore: deprecated_member_use
                      onChanged: (v) => setState(() => _primary = v ?? sport),
                    ),
                    const Text('주 종목'),
                  ]),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('등록 안 함'),
                  selected: selected == null,
                  onSelected: (_) => setState(() => _selected[sport] = null),
                ),
                for (final g in grades)
                  ChoiceChip(
                    label: Text(gradeLabel(g)),
                    selected: selected == g,
                    onSelected: (_) => setState(() => _selected[sport] = g),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('종목·등급 등록')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '활동하시는 종목과 등급을 알려주세요. 등록한 등급으로 출전 가능한 대회만 자동으로 보여드립니다.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    _sportSection(Sport.tennis),
                    _sportSection(Sport.futsal),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
              FilledButton(
                onPressed: _canSubmit && !_busy ? _submit : null,
                child: const Text('시작하기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
