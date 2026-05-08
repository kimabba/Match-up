import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/providers.dart';
import '../utils/grade_labels.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final sports = ref.watch(userSportsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('내 정보')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: const Text('이메일'),
            subtitle: Text(user?.email ?? '-'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.sports),
            title: const Text('등록 종목·등급'),
            trailing: TextButton(
              onPressed: () => context.push('/onboarding'),
              child: const Text('수정'),
            ),
          ),
          sports.when(
            loading: () => const ListTile(title: LinearProgressIndicator()),
            error: (e, _) => ListTile(title: Text('$e')),
            data: (list) => Column(
              children: [
                if (list.isEmpty)
                  const ListTile(title: Text('아직 등록된 종목이 없습니다.'))
                else
                  for (final s in list)
                    ListTile(
                      leading: Icon(s.sport == 'tennis'
                          ? Icons.sports_tennis
                          : Icons.sports_soccer),
                      title: Text(sportLabelFromString(s.sport)),
                      subtitle: Text(gradeLabel(s.grade)),
                      trailing: s.isPrimary
                          ? const Chip(label: Text('주 종목'))
                          : null,
                    ),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('알림'),
            subtitle: const Text('대회 D-3·신청 마감 알림 (즐겨찾기 기준)'),
            onTap: () {},
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('로그아웃', style: TextStyle(color: Colors.red)),
            onTap: () async {
              await ref.read(supabaseProvider).auth.signOut();
            },
          ),
        ],
      ),
    );
  }
}
