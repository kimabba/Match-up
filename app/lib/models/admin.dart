class CrawlAuditLog {
  final String id;
  final String source;
  final String status;
  final int fetchedCount;
  final int insertedCount;
  final int updatedCount;
  final String? error;
  final DateTime startedAt;
  final DateTime? finishedAt;

  CrawlAuditLog({
    required this.id,
    required this.source,
    required this.status,
    required this.fetchedCount,
    required this.insertedCount,
    required this.updatedCount,
    this.error,
    required this.startedAt,
    this.finishedAt,
  });

  factory CrawlAuditLog.fromJson(Map<String, dynamic> j) => CrawlAuditLog(
        id: j['id'] as String,
        source: j['source'] as String,
        status: j['status'] as String,
        fetchedCount: j['fetched_count'] as int? ?? 0,
        insertedCount: j['inserted_count'] as int? ?? 0,
        updatedCount: j['updated_count'] as int? ?? 0,
        error: j['error'] as String?,
        startedAt: DateTime.parse(j['started_at'] as String),
        finishedAt: j['finished_at'] != null
            ? DateTime.parse(j['finished_at'] as String)
            : null,
      );
}
