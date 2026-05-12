import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/tournament.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../utils/grade_labels.dart';
import '../widgets/app_chip.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/tournament_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sports = ref.watch(userSportsProvider);
    final tournaments = ref.watch(homeTournamentsProvider);
    final favorites = ref.watch(favoriteIdsProvider);
    final selected = ref.watch(selectedSportProvider);

    final tournamentCount =
        tournaments.maybeWhen(data: (l) => l.length, orElse: () => 0);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _HomeHeroSliver(
            sports: sports,
            count: tournamentCount,
            selected: selected,
            onSportChanged: (s) {
              ref.read(selectedSportProvider.notifier).state = s;
              ref.invalidate(homeTournamentsProvider);
            },
            onRefresh: () {
              ref.invalidate(homeTournamentsProvider);
              ref.invalidate(favoriteIdsProvider);
            },
          ),
          _TournamentListSliver(
            tournaments: tournaments,
            favorites: favorites,
            ref: ref,
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// Hero SliverAppBar — Big Number + 종목 필터 칩
// ────────────────────────────────────────────────────────────

class _HomeHeroSliver extends StatelessWidget {
  final AsyncValue<List<UserSport>> sports;
  final int count;
  final String? selected;
  final ValueChanged<String?> onSportChanged;
  final VoidCallback onRefresh;

  const _HomeHeroSliver({
    required this.sports,
    required this.count,
    required this.selected,
    required this.onSportChanged,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final showToggle =
        sports.maybeWhen(data: (l) => l.length > 1, orElse: () => false);

    return SliverAppBar(
      expandedHeight: showToggle ? 200 : 172,
      pinned: true,
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      title: const Text('Match-up'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: onRefresh,
          tooltip: '새로고침',
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.primary, cs.primaryContainer],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                kToolbarHeight + AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Big Number
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$count',
                        style: tt.displayMedium?.copyWith(
                          color: cs.onPrimary,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '개 대회 출전 가능',
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onPrimary.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '내 등급에 맞는 대회만 필터링했어요',
                    style: tt.bodySmall?.copyWith(
                      color: cs.onPrimary.withValues(alpha: 0.7),
                    ),
                  ),
                  if (showToggle) ...[
                    const SizedBox(height: AppSpacing.md),
                    _SportChipRow(
                      sports: sports.valueOrNull ?? const [],
                      selected: selected,
                      onChanged: onSportChanged,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SportChipRow extends StatelessWidget {
  final List<UserSport> sports;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _SportChipRow({
    required this.sports,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          AppChip(
            label: '전체',
            selected: selected == null,
            selectedColor: cs.onPrimary.withValues(alpha: 0.2),
            onTap: () => onChanged(null),
          ),
          const SizedBox(width: AppSpacing.sm),
          ...sports.map(
            (s) => Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: AppChip(
                label: sportLabelFromString(s.sport),
                selected: selected == s.sport,
                selectedColor: cs.onPrimary.withValues(alpha: 0.2),
                leadingIcon: s.sport == 'tennis'
                    ? Icons.sports_tennis_rounded
                    : Icons.sports_soccer_rounded,
                onTap: () => onChanged(s.sport),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 대회 리스트
// ────────────────────────────────────────────────────────────

class _TournamentListSliver extends StatelessWidget {
  final AsyncValue<List<Tournament>> tournaments;
  final AsyncValue<Set<String>> favorites;
  final WidgetRef ref;

  const _TournamentListSliver({
    required this.tournaments,
    required this.favorites,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return tournaments.when(
      loading: () => const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => SliverFillRemaining(
        child: Center(child: Text('$e')),
      ),
      data: (list) {
        if (list.isEmpty) {
          return SliverFillRemaining(
            child: AppEmptyState(
              icon: Icons.search_off_rounded,
              title: '출전 가능한 대회 없음',
              description: '내 등급으로 출전 가능한 대회가 없습니다.',
              actionLabel: '전체 대회 보기',
              onAction: () => context.go('/tournaments'),
            ),
          );
        }

        final favs = favorites.valueOrNull ?? const <String>{};
        return SliverPadding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.lg,
          ),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
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
              childCount: list.length,
            ),
          ),
        );
      },
    );
  }
}
