import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models/tournament.dart';

/// Edge Functions REST + SSE 클라이언트.
class ApiService {
  ApiService(this._supabase);

  final SupabaseClient _supabase;

  Map<String, String> _authHeaders() {
    final token = _supabase.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(AppConfig.apiBaseUrl);
    return base.replace(
      path: '${base.path}/$path',
      queryParameters: query?..removeWhere((_, v) => v.isEmpty),
    );
  }

  // ===== tournaments =====

  Future<List<Tournament>> searchTournaments({
    String? sport,
    String? region,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool onlyMyGrade = true,
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await http.get(
      _uri('tournaments-search', {
        if (sport != null) 'sport': sport,
        if (region != null) 'region': region,
        if (dateFrom != null) 'date_from': _ymd(dateFrom),
        if (dateTo != null) 'date_to': _ymd(dateTo),
        'only_my_grade': onlyMyGrade.toString(),
        if (query != null && query.isNotEmpty) 'q': query,
        'limit': limit.toString(),
        'offset': offset.toString(),
      }),
      headers: _authHeaders(),
    );
    _check(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['tournaments'] as List)
        .map((e) => Tournament.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Tournament> submitTournament(Map<String, dynamic> payload) async {
    final res = await http.post(
      _uri('tournaments-submit'),
      headers: _authHeaders(),
      body: jsonEncode(payload),
    );
    _check(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return Tournament.fromJson(body['tournament'] as Map<String, dynamic>);
  }

  Future<void> approveTournament(String id, {bool approve = true, String? reason}) async {
    final res = await http.post(
      _uri('tournaments-approve'),
      headers: _authHeaders(),
      body: jsonEncode({
        'id': id,
        'action': approve ? 'approve' : 'reject',
        if (reason != null) 'reason': reason,
      }),
    );
    _check(res);
  }

  // ===== favorites =====
  Future<void> toggleFavorite(String tournamentId, bool favorite) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');

    if (favorite) {
      await _supabase.from('tournament_favorites').upsert({
        'user_id': userId,
        'tournament_id': tournamentId,
      });
    } else {
      await _supabase
          .from('tournament_favorites')
          .delete()
          .eq('user_id', userId)
          .eq('tournament_id', tournamentId);
    }
  }

  Future<Set<String>> myFavoriteIds() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return {};
    final rows = await _supabase
        .from('tournament_favorites')
        .select('tournament_id')
        .eq('user_id', userId);
    return rows.map((r) => r['tournament_id'] as String).toSet();
  }

  // ===== clubs =====
  Future<List<Club>> searchClubs({String? sport, String? region, String? q}) async {
    final res = await http.get(
      _uri('clubs-search', {
        if (sport != null) 'sport': sport,
        if (region != null) 'region': region,
        if (q != null && q.isNotEmpty) 'q': q,
      }),
      headers: _authHeaders(),
    );
    _check(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['clubs'] as List)
        .map((e) => Club.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ===== rules =====
  Future<List<RuleArticle>> listRules(String sport) async {
    final rows = await _supabase
        .from('rule_articles')
        .select()
        .eq('sport', sport)
        .eq('published', true)
        .order('order_idx');
    return rows.map((r) => RuleArticle.fromJson(r)).toList();
  }

  // ===== chat (SSE) =====

  /// SSE 스트리밍. 이벤트 라인을 yield 한다.
  Stream<ChatStreamEvent> chat({
    required String message,
    String? conversationId,
    bool enableSearch = true,
  }) async* {
    final client = HttpClient();
    try {
      final req = await client.postUrl(_uri('chat'));
      _authHeaders().forEach(req.headers.set);
      req.headers.set('Accept', 'text/event-stream');
      req.write(jsonEncode({
        'message': message,
        if (conversationId != null) 'conversation_id': conversationId,
        'enable_search': enableSearch,
      }));
      final res = await req.close();
      if (res.statusCode != 200) {
        final body = await res.transform(utf8.decoder).join();
        throw HttpException('chat ${res.statusCode}: $body');
      }
      String buffer = '';
      String currentEvent = 'message';
      await for (final chunk in res.transform(utf8.decoder)) {
        buffer += chunk;
        while (true) {
          final idx = buffer.indexOf('\n\n');
          if (idx < 0) break;
          final block = buffer.substring(0, idx);
          buffer = buffer.substring(idx + 2);
          for (final line in block.split('\n')) {
            if (line.startsWith('event:')) {
              currentEvent = line.substring(6).trim();
            } else if (line.startsWith('data:')) {
              final raw = line.substring(5).trim();
              if (raw.isEmpty) continue;
              try {
                final data = jsonDecode(raw) as Map<String, dynamic>;
                yield ChatStreamEvent(currentEvent, data);
              } catch (_) {/* skip malformed chunk */}
            }
          }
        }
      }
    } finally {
      client.close();
    }
  }

  // ===== devices =====
  Future<void> registerDeviceToken(String token, String platform) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    await _supabase.from('device_tokens').upsert({
      'user_id': userId,
      'token': token,
      'platform': platform,
      'enabled': true,
    });
  }

  // ===== user_sports =====
  Future<List<UserSport>> myUserSports() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];
    final rows = await _supabase
        .from('user_sports')
        .select()
        .eq('user_id', userId)
        .order('is_primary', ascending: false);
    return rows.map((r) => UserSport.fromJson(r)).toList();
  }

  Future<void> saveUserSports(List<UserSport> sports) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');

    await _supabase.from('user_sports').delete().eq('user_id', userId);
    if (sports.isNotEmpty) {
      await _supabase
          .from('user_sports')
          .insert(sports.map((s) => s.toInsert(userId)).toList());
    }
  }

  // ===== regions =====
  Future<List<Region>> listRegions() async {
    final rows = await _supabase.from('regions').select().order('code');
    return rows.map((r) => Region.fromJson(r)).toList();
  }

  // ===== user_tennis_orgs (multi-org) =====
  Future<List<UserTennisOrg>> myTennisOrgs() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];
    final rows = await _supabase
        .from('user_tennis_orgs')
        .select()
        .eq('user_id', userId)
        .order('is_primary', ascending: false);
    return rows.map((r) => UserTennisOrg.fromJson(r)).toList();
  }

  /// 협회 등록을 일괄 갱신 (delete-all-then-insert).
  /// 한 번에 N개 협회를 등록할 때 사용.
  Future<void> saveTennisOrgs(List<UserTennisOrg> orgs) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');

    await _supabase.from('user_tennis_orgs').delete().eq('user_id', userId);
    if (orgs.isNotEmpty) {
      await _supabase
          .from('user_tennis_orgs')
          .insert(orgs.map((o) => o.toUpsert(userId)).toList());
    }
  }

  /// 단일 협회 추가/갱신 (upsert).
  Future<void> upsertTennisOrg(UserTennisOrg org) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');
    await _supabase.from('user_tennis_orgs').upsert(org.toUpsert(userId));
  }

  /// 단일 협회 삭제.
  Future<void> deleteTennisOrg(String org) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');
    await _supabase
        .from('user_tennis_orgs')
        .delete()
        .eq('user_id', userId)
        .eq('org', org);
  }

  // ===== helpers =====
  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _check(http.Response res) {
    if (res.statusCode >= 400) {
      throw HttpException('${res.statusCode}: ${res.body}');
    }
  }
}

class ChatStreamEvent {
  final String event;
  final Map<String, dynamic> data;
  ChatStreamEvent(this.event, this.data);
}
