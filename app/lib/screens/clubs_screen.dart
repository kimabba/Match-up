import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/tournament.dart';
import '../state/providers.dart';
import '../utils/grade_labels.dart';

class ClubsScreen extends ConsumerStatefulWidget {
  const ClubsScreen({super.key});

  @override
  ConsumerState<ClubsScreen> createState() => _ClubsScreenState();
}

class _ClubsScreenState extends ConsumerState<ClubsScreen> {
  String? _sport;
  String _q = '';
  List<Club>? _clubs;
  bool _loading = false;

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await ref.read(apiProvider).searchClubs(sport: _sport, q: _q);
    if (mounted) {
      setState(() {
        _clubs = list;
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('동호회·클럽')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: '클럽명·설명 검색',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => _q = v,
                  onSubmitted: (_) => _load(),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  ChoiceChip(
                    label: const Text('전체'),
                    selected: _sport == null,
                    onSelected: (_) {
                      setState(() => _sport = null);
                      _load();
                    },
                  ),
                  const SizedBox(width: 4),
                  ChoiceChip(
                    label: const Text('테니스'),
                    selected: _sport == 'tennis',
                    onSelected: (_) {
                      setState(() => _sport = 'tennis');
                      _load();
                    },
                  ),
                  const SizedBox(width: 4),
                  ChoiceChip(
                    label: const Text('풋살'),
                    selected: _sport == 'futsal',
                    onSelected: (_) {
                      setState(() => _sport = 'futsal');
                      _load();
                    },
                  ),
                ]),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: _clubs == null
                ? const SizedBox.shrink()
                : _clubs!.isEmpty
                    ? const Center(child: Text('등록된 클럽이 없습니다.'))
                    : ListView.builder(
                        itemCount: _clubs!.length,
                        itemBuilder: (_, i) {
                          final c = _clubs![i];
                          return Card(
                            child: ListTile(
                              leading: Icon(c.sport == 'tennis'
                                  ? Icons.sports_tennis
                                  : Icons.sports_soccer),
                              title: Text(c.name),
                              subtitle: Text([
                                sportLabelFromString(c.sport),
                                if (c.region != null) c.region,
                                if (c.address != null) c.address,
                              ].whereType<String>().join(' · ')),
                              trailing: c.website != null
                                  ? IconButton(
                                      icon: const Icon(Icons.open_in_new),
                                      onPressed: () => launchUrl(
                                        Uri.parse(c.website!),
                                        mode: LaunchMode.externalApplication,
                                      ),
                                    )
                                  : null,
                              onTap: () {
                                showModalBottomSheet(
                                  context: context,
                                  builder: (_) => Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(c.name,
                                            style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 8),
                                        if (c.contact != null) Text('연락처: ${c.contact!}'),
                                        if (c.description != null) ...[
                                          const SizedBox(height: 8),
                                          Text(c.description!),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
