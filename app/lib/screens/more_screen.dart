import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/providers.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;
    final colorScheme = Theme.of(context).colorScheme;

    final items = [
      _MenuItem(
        icon: Icons.menu_book_outlined,
        label: '룰북',
        subtitle: '종목별 규칙 안내',
        onTap: () => context.go('/rules'),
      ),
      if (!kIsWeb)
        _MenuItem(
          icon: Icons.speed_rounded,
          label: '스피드건',
          subtitle: '공 속도 측정',
          onTap: () => context.go('/speed-gun'),
        ),
      _MenuItem(
        icon: Icons.person_outline,
        label: '내정보',
        subtitle: '프로필 및 설정',
        onTap: () => context.go('/profile'),
      ),
      if (isAdmin)
        _MenuItem(
          icon: Icons.admin_panel_settings_outlined,
          label: '어드민',
          subtitle: '관리자 메뉴',
          onTap: () => context.go('/admin'),
        ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('더보기')),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (context, i) {
          final item = items[i];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(item.icon, color: colorScheme.onPrimaryContainer),
            ),
            title: Text(item.label),
            subtitle: Text(item.subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: item.onTap,
          );
        },
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });
}
