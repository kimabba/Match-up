import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/admin.dart';
import '../../state/providers.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  Timer? _refreshTimer;

  List<CrawlAuditLog> _logs = [];
  bool _loadingLogs = false;

  List<Map<String, dynamic>> _drafts = [];
  bool _loadingDrafts = false;

  // Tab 3: track running state per source
  final Map<String, bool> _running = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(_onTabChanged);
    // Load initial data for tab 0
    _startRefreshTimer();
    _loadLogs();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tab.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tab.index == 0) {
      _startRefreshTimer();
      _loadLogs();
    } else {
      _cancelRefreshTimer();
      if (_tab.index == 1) {
        _loadDrafts();
      }
    }
  }

  void _startRefreshTimer() {
    _cancelRefreshTimer();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadLogs();
    });
  }

  void _cancelRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> _loadLogs() async {
    if (_loadingLogs) return;
    if (mounted) setState(() => _loadingLogs = true);
    try {
      final api = ref.read(apiProvider);
      final logs = await api.crawlAuditLogs();
      if (mounted) setState(() => _logs = logs);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('로그 로드 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _loadingLogs = false);
    }
  }

  Future<void> _loadDrafts() async {
    if (_loadingDrafts) return;
    if (mounted) setState(() => _loadingDrafts = true);
    try {
      final supabase = ref.read(supabaseProvider);
      final rows = await supabase
          .from('tournaments')
          .select()
          .eq('status', 'draft')
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() => _drafts = List<Map<String, dynamic>>.from(rows));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Draft 로드 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _loadingDrafts = false);
    }
  }

  Future<void> _approve(String id) async {
    try {
      final api = ref.read(apiProvider);
      await api.approveTournament(id, approve: true);
      await _loadDrafts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('승인 실패: $e')));
      }
    }
  }

  Future<void> _reject(String id) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('거절 사유'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(hintText: '사유를 입력하세요'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('거절'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final api = ref.read(apiProvider);
      final reason =
          reasonController.text.trim().isEmpty ? null : reasonController.text.trim();
      await api.approveTournament(id, approve: false, reason: reason);
      await _loadDrafts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('거절 실패: $e')));
      }
    }
  }

  Future<void> _invokeCrawler(String source) async {
    if (_running[source] == true) return;
    if (mounted) setState(() => _running[source] = true);
    try {
      final api = ref.read(apiProvider);
      final result = await api.invokeCrawler(source);
      if (mounted) {
        final fetched = result['fetched'] ?? result['fetched_count'] ?? 0;
        final inserted = result['inserted'] ?? result['inserted_count'] ?? 0;
        final updated = result['updated'] ?? result['updated_count'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '$source 완료 — fetched: $fetched, inserted: $inserted, updated: $updated'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$source 실행 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _running[source] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('관리자'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: '크롤 현황'),
            Tab(text: 'Draft 승인'),
            Tab(text: '수동 실행'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildLogsTab(),
          _buildDraftsTab(),
          _buildManualTab(),
        ],
      ),
    );
  }

  // ── Tab 1: Crawl History ──────────────────────────────────────────────────

  Widget _buildLogsTab() {
    if (_loadingLogs && _logs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_logs.isEmpty) {
      return const Center(child: Text('로그 없음'));
    }
    return RefreshIndicator(
      onRefresh: _loadLogs,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _logs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _LogCard(log: _logs[i]),
      ),
    );
  }

  // ── Tab 2: Draft Approval ─────────────────────────────────────────────────

  Widget _buildDraftsTab() {
    if (_loadingDrafts && _drafts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_drafts.isEmpty) {
      return const Center(child: Text('승인 대기 대회 없음'));
    }
    return RefreshIndicator(
      onRefresh: _loadDrafts,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _drafts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final t = _drafts[i];
          final id = t['id'] as String;
          final title = t['title'] as String? ?? '(제목 없음)';
          final sport = t['sport'] as String? ?? '';
          final date = t['start_date']?.toString().substring(0, 10) ?? '';
          final region = t['region'] as String? ?? '';
          final sourceUrl = t['source_url'] as String? ?? '';
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('$sport · $date · $region',
                      style: Theme.of(context).textTheme.bodySmall),
                  if (sourceUrl.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(sourceUrl,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: () => _approve(id),
                        child: const Text('승인'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => _reject(id),
                        child: const Text('거절'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Tab 3: Manual Trigger ─────────────────────────────────────────────────

  Widget _buildManualTab() {
    const sources = [
      'crawl-tennis-gwangju',
      'crawl-tennis-jeonnam',
      'crawl-tennis-korea',
    ];
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: sources.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final source = sources[i];
        final isRunning = _running[source] == true;
        return Card(
          child: ListTile(
            title: Text(source),
            trailing: isRunning
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FilledButton(
                    onPressed: isRunning ? null : () => _invokeCrawler(source),
                    child: const Text('지금 실행'),
                  ),
          ),
        );
      },
    );
  }
}

// ── Log card widget ───────────────────────────────────────────────────────────

class _LogCard extends StatelessWidget {
  const _LogCard({required this.log});
  final CrawlAuditLog log;

  Color _statusColor(String status) {
    switch (status) {
      case 'running':
        return Colors.blue;
      case 'success':
        return Colors.green;
      case 'partial':
        return Colors.orange;
      case 'failed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(log.status);
    final started = log.startedAt.toLocal();
    final ts =
        '${started.year}-${started.month.toString().padLeft(2, '0')}-${started.day.toString().padLeft(2, '0')} '
        '${started.hour.toString().padLeft(2, '0')}:${started.minute.toString().padLeft(2, '0')}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(log.source,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color),
                  ),
                  child: Text(log.status,
                      style: TextStyle(color: color, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(ts, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
                'fetched: ${log.fetchedCount}  inserted: ${log.insertedCount}  updated: ${log.updatedCount}',
                style: Theme.of(context).textTheme.bodySmall),
            if (log.error != null) ...[
              const SizedBox(height: 4),
              Text(log.error!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}
