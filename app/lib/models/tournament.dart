class Tournament {
  final String id;
  final String sport;
  final String title;
  final String? organizer;
  final String? description;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime? applicationDeadline;
  final String? region;
  final String? location;
  final List<String> eligibleGrades;
  final int? entryFee;
  final String? prize;
  final String? format;
  final String? sourceUrl;
  final String status;

  Tournament({
    required this.id,
    required this.sport,
    required this.title,
    this.organizer,
    this.description,
    required this.startDate,
    this.endDate,
    this.applicationDeadline,
    this.region,
    this.location,
    required this.eligibleGrades,
    this.entryFee,
    this.prize,
    this.format,
    this.sourceUrl,
    required this.status,
  });

  factory Tournament.fromJson(Map<String, dynamic> j) {
    final grades = (j['eligible_grades'] as List?)?.cast<String>() ?? const [];
    return Tournament(
      id: j['id'] as String,
      sport: j['sport'] as String,
      title: j['title'] as String,
      organizer: j['organizer'] as String?,
      description: j['description'] as String?,
      startDate: DateTime.parse(j['start_date'] as String),
      endDate: j['end_date'] != null ? DateTime.parse(j['end_date']) : null,
      applicationDeadline: j['application_deadline'] != null
          ? DateTime.parse(j['application_deadline'])
          : null,
      region: j['region'] as String?,
      location: j['location'] as String?,
      eligibleGrades: grades,
      entryFee: j['entry_fee'] as int?,
      prize: j['prize'] as String?,
      format: j['format'] as String?,
      sourceUrl: j['source_url'] as String?,
      status: j['status'] as String,
    );
  }
}

class Club {
  final String id;
  final String sport;
  final String name;
  final String? region;
  final String? address;
  final String? contact;
  final String? website;
  final String? description;

  Club({
    required this.id,
    required this.sport,
    required this.name,
    this.region,
    this.address,
    this.contact,
    this.website,
    this.description,
  });

  factory Club.fromJson(Map<String, dynamic> j) => Club(
        id: j['id'] as String,
        sport: j['sport'] as String,
        name: j['name'] as String,
        region: j['region'] as String?,
        address: j['address'] as String?,
        contact: j['contact'] as String?,
        website: j['website'] as String?,
        description: j['description'] as String?,
      );
}

class RuleArticle {
  final String id;
  final String sport;
  final String category;
  final String title;
  final String body;

  RuleArticle({
    required this.id,
    required this.sport,
    required this.category,
    required this.title,
    required this.body,
  });

  factory RuleArticle.fromJson(Map<String, dynamic> j) => RuleArticle(
        id: j['id'] as String,
        sport: j['sport'] as String,
        category: j['category'] as String,
        title: j['title'] as String,
        body: j['body'] as String,
      );
}

class UserSport {
  final String sport;   // 'tennis' / 'futsal'
  final String grade;   // 'div3' / 'intermediate' 등
  final bool isPrimary;

  UserSport({required this.sport, required this.grade, this.isPrimary = false});

  factory UserSport.fromJson(Map<String, dynamic> j) => UserSport(
        sport: j['sport'] as String,
        grade: j['grade'] as String,
        isPrimary: j['is_primary'] as bool? ?? false,
      );

  Map<String, dynamic> toInsert(String userId) => {
        'user_id': userId,
        'sport': sport,
        'grade': grade,
        'is_primary': isPrimary,
      };
}

class ChatMessage {
  final String id;
  final String role; // 'user' | 'assistant'
  final String content;
  final List<dynamic> citations;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.citations,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        role: j['role'] as String,
        content: j['content'] as String,
        citations: (j['citations'] as List?) ?? const [],
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}
