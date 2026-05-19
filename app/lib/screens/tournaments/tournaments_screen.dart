import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/tournament.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/tournament_card.dart';

class TournamentsScreen extends ConsumerStatefulWidget {
  const TournamentsScreen({super.key});

  @override
  ConsumerState<TournamentsScreen> createState() => _TournamentsScreenState();
}

class _TournamentsScreenState extends ConsumerState<TournamentsScreen> {
  bool _onlyMyGrade = false;
  String _q = '';
  List<Tournament>? _results;
  bool _loading = false;

  Future<void> _search() async {
    setState(() => _loading = true);
    final api = ref.read(apiProvider);
    final res = await api.searchTournaments(
      sport: ref.read(activeSportProvider),
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
    final cs = Theme.of(context).colorScheme;
    final favorites = ref.watch(favoriteIdsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('전체 대회'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: '대회 제보',
            onPressed: () => context.push('/tournaments/submit'),
          ),
        ],
      ),
      body: Column(
        children: [
          const _MyGradeSection(),
          // 검색 + 필터 영역
          Container(
            color: cs.surfaceContainerLowest,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Column(
              children: [
                // 검색창
                TextField(
                  decoration: InputDecoration(
                    hintText: '대회명·주최·설명 검색',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: cs.surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderRadius: AppRadius.card,
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                  ),
                  onChanged: (v) => _q = v,
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Transform.scale(
                      scale: 0.85,
                      child: Switch(
                        value: _onlyMyGrade,
                        onChanged: (v) {
                          setState(() => _onlyMyGrade = v);
                          _search();
                        },
                      ),
                    ),
                    Text(
                      '내 등급',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_loading) LinearProgressIndicator(color: cs.primary),
          // 결과 리스트
          Expanded(
            child: _results == null
                ? const SizedBox.shrink()
                : _results!.isEmpty
                    ? AppEmptyState(
                        icon: Icons.search_off_rounded,
                        title: '검색 결과 없음',
                        description: '다른 검색어나 필터로 시도해 보세요.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.lg,
                        ),
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

class _MyGradeSection extends ConsumerWidget {
  const _MyGradeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tournaments = ref.watch(homeTournamentsProvider);
    final favorites = ref.watch(favoriteIdsProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
          child: Text('내 등급 추천 대회', style: tt.titleMedium),
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

