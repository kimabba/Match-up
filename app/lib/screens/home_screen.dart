import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/tournament.dart';
import '../state/providers.dart';
import '../utils/grade_labels.dart';
import '../widgets/tournament_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sports = ref.watch(userSportsProvider);
    final tournaments = ref.watch(homeTournamentsProvider);
    final favorites = ref.watch(favoriteIdsProvider);
    final selected = ref.watch(selectedSportProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('나에게 맞는 대회'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(homeTournamentsProvider);
              ref.invalidate(favoriteIdsProvider);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          sports.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(8),
              child: Text('$e', style: const TextStyle(color: Colors.red)),
            ),
            data: (list) => _SportToggle(
              sports: list,
              selected: selected,
              onChanged: (s) {
                ref.read(selectedSportProvider.notifier).state = s;
                ref.invalidate(homeTournamentsProvider);
              },
            ),
          ),
          Expanded(
            child: tournaments.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (list) {
                if (list.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.search_off, size: 48, color: Colors.black38),
                          const SizedBox(height: 12),
                          const Text(
                            '내 등급으로 출전 가능한 대회가 없습니다.',
                            textAlign: TextAlign.center,
                          ),
                          TextButton(
                            onPressed: () => context.go('/tournaments'),
                            child: const Text('전체 대회 보기'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final favs = favorites.valueOrNull ?? const <String>{};
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(homeTournamentsProvider);
                    ref.invalidate(favoriteIdsProvider);
                    await ref.read(homeTournamentsProvider.future);
                  },
                  child: ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final t = list[i];
                      return TournamentCard(
                        tournament: t,
                        isFavorite: favs.contains(t.id),
                        onTap: () => context.push('/tournaments/${t.id}'),
                        onFavoriteToggle: () async {
                          final api = ref.read(apiProvider);
                          await api.toggleFavorite(t.id, !favs.contains(t.id));
                          ref.invalidate(favoriteIdsProvider);
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SportToggle extends StatelessWidget {
  const _SportToggle({
    required this.sports,
    required this.selected,
    required this.onChanged,
  });

  final List<UserSport> sports;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (sports.length <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: const Text('전체'),
            selected: selected == null,
            onSelected: (_) => onChanged(null),
          ),
          for (final s in sports)
            ChoiceChip(
              label: Text(sportLabelFromString(s.sport)),
              selected: selected == s.sport,
              onSelected: (_) => onChanged(s.sport),
            ),
        ],
      ),
    );
  }
}
