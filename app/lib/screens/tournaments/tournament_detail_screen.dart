import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/tournament.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart';
import '../../widgets/app_card.dart';


class TournamentDetailScreen extends ConsumerStatefulWidget {
  const TournamentDetailScreen({super.key, required this.tournamentId});
  final String tournamentId;

  @override
  ConsumerState<TournamentDetailScreen> createState() =>
      _TournamentDetailScreenState();
}

class _TournamentDetailScreenState
    extends ConsumerState<TournamentDetailScreen> {
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
      final row = await supa
          .from('tournaments')
          .select()
          .eq('id', widget.tournamentId)
          .single();
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
    final cs = Theme.of(context).colorScheme;
    final favorites = ref.watch(favoriteIdsProvider);
    final isFav = (favorites.valueOrNull ?? const {}).contains(widget.tournamentId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('대회 상세'),
        actions: [
          if (_t != null)
            IconButton(
              icon: Icon(
                isFav ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                color: isFav ? cs.primary : null,
              ),
              onPressed: () async {
                HapticFeedback.lightImpact();
                await ref.read(apiProvider).toggleFavorite(widget.tournamentId, !isFav);
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
                  : _DetailBody(t: _t!, df: _df),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final Tournament t;
  final DateFormat df;
  const _DetailBody({required this.t, required this.df});

  static final _feeFormat = NumberFormat.decimalPattern('ko');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isTennis = t.sport == 'tennis';
    final accentColor = isTennis ? cs.primary : cs.tertiary;
    final grades = (t.divisionLabelLocal?.isNotEmpty == true)
        ? t.divisionLabelLocal!
        : formatEligibleGrades(t.eligibleGrades);

    final hasDescription = t.description != null &&
        t.description!.trim().isNotEmpty &&
        !t.description!.startsWith('참가부서:');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 타이틀 + 종목 배지
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  isTennis
                      ? Icons.sports_tennis_rounded
                      : Icons.sports_soccer_rounded,
                  color: accentColor,
                  size: 26,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(t.title, style: tt.headlineSmall),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // 1. 기본 정보 (기본 열림)
          _AccordionSection(
            icon: Icons.info_outline_rounded,
            title: '기본 정보',
            initiallyExpanded: true,
            children: [
              _InfoRow(icon: Icons.sports_rounded, label: '종목', value: sportLabelFromString(t.sport), accent: accentColor),
              _InfoRow(icon: Icons.calendar_today_rounded, label: '대회일', value: _dateText()),
              if (t.region != null)
                _InfoRow(icon: Icons.place_rounded, label: '지역', value: t.region!),
              if (t.location != null)
                _InfoRow(icon: Icons.location_on_rounded, label: '장소', value: t.location!),
              if (t.organizer != null)
                _InfoRow(icon: Icons.business_rounded, label: '주최', value: t.organizer!),
            ],
          ),

          // 2. 출전 등급
          _AccordionSection(
            icon: Icons.emoji_events_rounded,
            title: '출전 등급',
            initiallyExpanded: true,
            children: [
              _InfoRow(icon: Icons.emoji_events_rounded, label: '부서', value: grades, accent: accentColor),
              if (t.isJointEvent)
                _InfoRow(icon: Icons.groups_rounded, label: '통합', value: '통합 대회'),
            ],
          ),

          // 3. 참가 안내
          _AccordionSection(
            icon: Icons.how_to_reg_rounded,
            title: '참가 안내',
            initiallyExpanded: false,
            children: [
              if (t.applicationDeadline != null)
                _InfoRow(icon: Icons.event_busy_rounded, label: '신청 마감', value: df.format(t.applicationDeadline!), accent: cs.error),
              if (t.entryFee != null)
                _InfoRow(
                  icon: Icons.payments_rounded,
                  label: '참가비',
                  value: '${t.entryFeeUnit == 'per_person' ? '인당' : '팀당'} ${_feeFormat.format(t.entryFee!)}원',
                ),
              if (t.prize != null)
                _InfoRow(icon: Icons.workspace_premium_rounded, label: '시상', value: t.prize!),
              if (t.format != null)
                _InfoRow(icon: Icons.format_list_numbered_rounded, label: '진행 방식', value: t.format!),
              if (t.applicationDeadline == null && t.entryFee == null && t.prize == null && t.format == null)
                _InfoRow(icon: Icons.info_outline, label: '안내', value: '상세 참가 안내는 주최 측에 문의해 주세요.'),
            ],
          ),

          // 4. 대회 요강 (크롤된 상세 내용 → 정형화)
          if (hasDescription)
            _AccordionSection(
              icon: Icons.article_rounded,
              title: '대회 요강',
              initiallyExpanded: false,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final section in _parseDescription(t.description!))
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: section.isHeader
                              ? Padding(
                                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                                  child: Text(
                                    section.text,
                                    style: tt.labelLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: cs.primary,
                                    ),
                                  ),
                                )
                              : Text(
                                  section.text,
                                  style: tt.bodySmall?.copyWith(
                                    height: 1.6,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                        ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ),
                ),
              ],
            ),

          const SizedBox(height: AppSpacing.xxxl),
        ],
      ),
    );
  }

  String _dateText() {
    final start = df.format(t.startDate);
    final end = t.endDate;
    if (end == null || _isSameDay(t.startDate, end)) return start;
    return '$start ~ ${df.format(end)}';
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DescSection {
  final String text;
  final bool isHeader;
  const _DescSection(this.text, {this.isHeader = false});
}

/// 크롤된 대회 요강 텍스트를 키워드 기반으로 섹션 분리
List<_DescSection> _parseDescription(String raw) {
  // 핵심 키워드 앞에 줄바꿈 삽입
  var text = raw
      .replaceAllMapped(
        RegExp(r'(장\s*소|장\s*:)'),
        (m) => '\n📍 장소: ',
      )
      .replaceAllMapped(
        RegExp(r'(주\s*최|주최\s*:)'),
        (m) => '\n🏢 주최: ',
      )
      .replaceAllMapped(
        RegExp(r'(주\s*관|주관\s*:)'),
        (m) => '\n🏢 주관: ',
      )
      .replaceAllMapped(
        RegExp(r'(참가비|참\s*가\s*비\s*:)'),
        (m) => '\n💰 참가비: ',
      )
      .replaceAllMapped(
        RegExp(r'(입금계좌|입금\s*계좌\s*:)'),
        (m) => '\n🏦 입금계좌: ',
      )
      .replaceAllMapped(
        RegExp(r'(접수\s*마감|신청\s*마감)'),
        (m) => '\n⏰ 접수마감: ',
      )
      .replaceAllMapped(
        RegExp(r'(사\s*용\s*구|공\s*인\s*구)'),
        (m) => '\n🎾 사용구: ',
      )
      .replaceAllMapped(
        RegExp(r'(경기\s*종목|경기종목)'),
        (m) => '\n🏅 경기종목:\n',
      )
      .replaceAll(RegExp(r'[◈◇★●▶]\s*'), '\n• ')
      .replaceAll(RegExp(r'※\s*'), '\n※ ');

  final lines = text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  final sections = <_DescSection>[];
  final headerPattern = RegExp(r'^(📍|🏢|💰|🏦|⏰|🎾|🏅)');

  for (final line in lines) {
    if (headerPattern.hasMatch(line)) {
      sections.add(_DescSection(line, isHeader: true));
    } else {
      sections.add(_DescSection(line));
    }
  }

  return sections;
}

class _AccordionSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool initiallyExpanded;
  final List<Widget> children;

  const _AccordionSection({
    required this.icon,
    required this.title,
    required this.children,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          childrenPadding: const EdgeInsets.only(bottom: AppSpacing.md),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Icon(icon, size: 20, color: cs.primary),
          title: Text(
            title,
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          children: children,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? accent;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final c = accent ?? cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: AppSpacing.md),
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(value, style: tt.bodyMedium),
          ),
        ],
      ),
    );
  }
}

