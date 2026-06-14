class ScheduleShare {
  final String id;
  final String sharedBy;
  final String sharedWith;
  final String? sharedByName;
  final String? sharedWithName;
  final String eventType; // tournament, club_event
  final String eventId;
  final String status; // pending, accepted, declined
  final DateTime createdAt;

  const ScheduleShare({
    required this.id,
    required this.sharedBy,
    required this.sharedWith,
    this.sharedByName,
    this.sharedWithName,
    required this.eventType,
    required this.eventId,
    required this.status,
    required this.createdAt,
  });

  factory ScheduleShare.fromJson(Map<String, dynamic> j) {
    final by = j['shared_by_user'] as Map<String, dynamic>?;
    final with_ = j['shared_with_user'] as Map<String, dynamic>?;
    return ScheduleShare(
      id: j['id'] as String,
      sharedBy: j['shared_by'] as String,
      sharedWith: j['shared_with'] as String,
      sharedByName: by?['name'] as String?,
      sharedWithName: with_?['name'] as String?,
      eventType: j['event_type'] as String,
      eventId: j['event_id'] as String,
      status: (j['status'] as String?) ?? 'pending',
      createdAt: DateTime.parse(j['created_at'] as String),
    );
  }

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
}
