import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/tournament.dart';
import '../../state/providers.dart';
import '../../utils/grade_labels.dart';

class TournamentDetailScreen extends ConsumerStatefulWidget {
  const TournamentDetailScreen({super.key, required this.tournamentId});
  final String tournamentId;

  @override
  ConsumerState<TournamentDetailScreen> createState() => _TournamentDetailScreenState();
}

class _TournamentDetailScreenState extends ConsumerState<TournamentDetailScreen> {
  Tournament? _t;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final supa = ref.read(supabaseProvider);
      final row = await supa.from('tournaments').select().eq('id', widget.tournamentId).single();
      setState(() {
        _t = Tournament.fromJson(row);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  static final _df = DateFormat('yyyy년 M월 d일 (E)', 'ko');

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(favoriteIdsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('대회 상세'),
        actions: [
          if (_t != null)
            IconButton(
              icon: Icon(
                (favorites.valueOrNull ?? const {}).contains(_t!.id)
                    ? Icons.bookmark
                    : Icons.bookmark_outline,
              ),
              onPressed: () async {
                final isFav = (favorites.valueOrNull ?? const {}).contains(_t!.id);
                await ref.read(apiProvider).toggleFavorite(_t!.id, !isFav);
                ref.invalidate(favoriteIdsProvider);
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _t == null
                  ? const Center(child: Text('대회 정보 없음'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_t!.title,
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          _row(Icons.sports, sportLabelFromString(_t!.sport)),
                          _row(Icons.calendar_today, _df.format(_t!.startDate)),
                          if (_t!.applicationDeadline != null)
                            _row(Icons.event_busy,
                                '신청 마감: ${_df.format(_t!.applicationDeadline!)}'),
                          if (_t!.region != null) _row(Icons.place, _t!.region!),
                          if (_t!.location != null) _row(Icons.location_on, _t!.location!),
                          _row(
                            Icons.emoji_events,
                            '출전 등급: ${_t!.eligibleGrades.map(gradeLabel).join(', ')}',
                          ),
                          if (_t!.entryFee != null)
                            _row(Icons.attach_money, '참가비: ${_t!.entryFee}원'),
                          if (_t!.prize != null) _row(Icons.workspace_premium, _t!.prize!),
                          if (_t!.format != null) _row(Icons.format_list_numbered, _t!.format!),
                          if (_t!.organizer != null) _row(Icons.business, _t!.organizer!),
                          const Divider(height: 32),
                          if (_t!.description != null)
                            Text(_t!.description!, style: const TextStyle(height: 1.5)),
                          const SizedBox(height: 24),
                          if (_t!.sourceUrl != null)
                            FilledButton.tonalIcon(
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('원본 공고 열기'),
                              onPressed: () =>
                                  launchUrl(Uri.parse(_t!.sourceUrl!), mode: LaunchMode.externalApplication),
                            ),
                        ],
                      ),
                    ),
    );
  }

  Widget _row(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, size: 18, color: Colors.black54),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ]),
    );
  }
}
