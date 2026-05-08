import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/tournament.dart';
import '../utils/grade_labels.dart';

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
    final grades = tournament.eligibleGrades.map(gradeLabel).join(', ');
    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text(tournament.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(
                  tournament.sport == 'tennis'
                      ? Icons.sports_tennis
                      : Icons.sports_soccer,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(sportLabelFromString(tournament.sport)),
                const SizedBox(width: 12),
                const Icon(Icons.calendar_today_outlined, size: 14),
                const SizedBox(width: 4),
                Text(_df.format(tournament.startDate)),
                if (tournament.region != null) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.place_outlined, size: 14),
                  const SizedBox(width: 4),
                  Text(tournament.region!),
                ],
              ]),
              const SizedBox(height: 4),
              Text('출전 등급: $grades',
                  style: const TextStyle(color: Colors.black54, fontSize: 12)),
            ],
          ),
        ),
        trailing: onFavoriteToggle == null
            ? null
            : IconButton(
                icon: Icon(isFavorite ? Icons.bookmark : Icons.bookmark_outline),
                onPressed: onFavoriteToggle,
              ),
      ),
    );
  }
}
