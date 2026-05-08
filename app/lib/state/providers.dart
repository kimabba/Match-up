import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/tournament.dart';
import '../services/api.dart';

final supabaseProvider = Provider<SupabaseClient>((_) {
  return Supabase.instance.client;
});

final apiProvider = Provider<ApiService>((ref) {
  return ApiService(ref.watch(supabaseProvider));
});

/// 인증 상태 (Session 또는 null)
final authStateProvider = StreamProvider<AuthState>((ref) {
  final supa = ref.watch(supabaseProvider);
  return supa.auth.onAuthStateChange;
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(supabaseProvider).auth.currentUser;
});

/// 사용자 종목·등급 목록
final userSportsProvider = FutureProvider<List<UserSport>>((ref) async {
  // auth state 변경에 따라 invalidate
  ref.watch(authStateProvider);
  final api = ref.watch(apiProvider);
  return api.myUserSports();
});

/// 즐겨찾기 ID 집합
final favoriteIdsProvider = FutureProvider<Set<String>>((ref) async {
  ref.watch(authStateProvider);
  final api = ref.watch(apiProvider);
  return api.myFavoriteIds();
});

/// 현재 홈에서 보고 있는 종목 (다중 종목 사용자가 토글)
final selectedSportProvider = StateProvider<String?>((ref) => null);

/// 홈 자동 필터 결과
final homeTournamentsProvider = FutureProvider<List<Tournament>>((ref) async {
  ref.watch(authStateProvider);
  final api = ref.watch(apiProvider);
  final sport = ref.watch(selectedSportProvider);
  return api.searchTournaments(sport: sport, onlyMyGrade: true, limit: 50);
});
