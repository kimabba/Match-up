import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/tournament.dart';
import '../theme/tokens.dart';
import '../utils/grade_labels.dart';
import 'app_card.dart';

class TournamentCard extends StatelessWidget {
  const TournamentCard({
    super.key,
    required this.tournament,
    this.isFavorite = false,
    this.onTap,
    this.onFavoriteToggle,
  });

  final Tournament tournament;
  final bool isFavorite;
  final VoidCallback? onTap;
  final VoidCallback? onFavoriteToggle;

  static final _df = DateFormat('M월 d일 (E)', 'ko');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isTennis = tournament.sport == 'tennis';
    final accentColor = isTennis ? cs.primary : cs.tertiary;
    final grades = tournament.eligibleGrades.map(gradeLabel).join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: onTap,
        variant: AppCardVariant.elevated,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 종목 인디케이터 바
            Container(
              width: 4,
              height: 64,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(AppRadius.xs),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tournament.title,
                    style: tt.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: 2,
                    children: [
                      _MetaChip(
                        icon: isTennis
                            ? Icons.sports_tennis_rounded
                            : Icons.sports_soccer_rounded,
                        label: sportLabelFromString(tournament.sport),
                        color: accentColor,
                      ),
                      _MetaChip(
                        icon: Icons.calendar_today_rounded,
                        label: _df.format(tournament.startDate),
                      ),
                      if (tournament.region != null)
                        _MetaChip(
                          icon: Icons.place_rounded,
                          label: tournament.region!,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '출전: $grades',
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (onFavoriteToggle != null)
              _FavoriteButton(
                isFavorite: isFavorite,
                onTap: () {
                  HapticFeedback.lightImpact();
                  onFavoriteToggle!();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _MetaChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final c = color ?? cs.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: c),
        const SizedBox(width: 3),
        Text(label, style: tt.labelSmall?.copyWith(color: c)),
      ],
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  final bool isFavorite;
  final VoidCallback onTap;
  const _FavoriteButton({required this.isFavorite, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Icon(
          key: ValueKey(isFavorite),
          isFavorite ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
          color: isFavorite ? cs.primary : cs.onSurfaceVariant,
          size: 22,
        ),
      ),
    );
  }
}
