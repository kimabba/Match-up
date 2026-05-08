import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/tournament.dart';
import '../../state/providers.dart';
import '../../widgets/tournament_card.dart';

class TournamentsScreen extends ConsumerStatefulWidget {
  const TournamentsScreen({super.key});

  @override
  ConsumerState<TournamentsScreen> createState() => _TournamentsScreenState();
}

class _TournamentsScreenState extends ConsumerState<TournamentsScreen> {
  String? _sport;
  bool _onlyMyGrade = false;
  String _q = '';
  List<Tournament>? _results;
  bool _loading = false;

  Future<void> _search() async {
    setState(() => _loading = true);
    final api = ref.read(apiProvider);
    final res = await api.searchTournaments(
      sport: _sport,
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(favoriteIdsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('전체 대회'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '대회 제보',
            onPressed: () => context.push('/tournaments/submit'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: '대회명·주최·설명 검색',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => _q = v,
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  ChoiceChip(
                    label: const Text('전체 종목'),
                    selected: _sport == null,
                    onSelected: (_) {
                      setState(() => _sport = null);
                      _search();
                    },
                  ),
                  const SizedBox(width: 4),
                  ChoiceChip(
                    label: const Text('테니스'),
                    selected: _sport == 'tennis',
                    onSelected: (_) {
                      setState(() => _sport = 'tennis');
                      _search();
                    },
                  ),
                  const SizedBox(width: 4),
                  ChoiceChip(
                    label: const Text('풋살'),
                    selected: _sport == 'futsal',
                    onSelected: (_) {
                      setState(() => _sport = 'futsal');
                      _search();
                    },
                  ),
                  const Spacer(),
                  Row(children: [
                    Switch(
                      value: _onlyMyGrade,
                      onChanged: (v) {
                        setState(() => _onlyMyGrade = v);
                        _search();
                      },
                    ),
                    const Text('내 등급만'),
                  ]),
                ]),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: _results == null
                ? const SizedBox.shrink()
                : _results!.isEmpty
                    ? const Center(child: Text('결과 없음'))
                    : ListView.builder(
                        itemCount: _results!.length,
                        itemBuilder: (_, i) {
                          final t = _results![i];
                          final favs = favorites.valueOrNull ?? const <String>{};
                          return TournamentCard(
                            tournament: t,
                            isFavorite: favs.contains(t.id),
                            onTap: () => context.push('/tournaments/${t.id}'),
                            onFavoriteToggle: () async {
                              await ref
                                  .read(apiProvider)
                                  .toggleFavorite(t.id, !favs.contains(t.id));
                              ref.invalidate(favoriteIdsProvider);
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
