import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tournament.dart';
import '../state/providers.dart';

class RulesScreen extends ConsumerStatefulWidget {
  const RulesScreen({super.key});

  @override
  ConsumerState<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends ConsumerState<RulesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  Map<String, List<RuleArticle>>? _tennisByCat;
  Map<String, List<RuleArticle>>? _futsalByCat;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiProvider);
    final tennis = await api.listRules('tennis');
    final futsal = await api.listRules('futsal');

    if (!mounted) return;
    setState(() {
      _tennisByCat = _groupByCategory(tennis);
      _futsalByCat = _groupByCategory(futsal);
      _loading = false;
    });
  }

  Map<String, List<RuleArticle>> _groupByCategory(List<RuleArticle> list) {
    final out = <String, List<RuleArticle>>{};
    for (final r in list) {
      out.putIfAbsent(r.category, () => []).add(r);
    }
    return out;
  }

  Widget _categoryList(Map<String, List<RuleArticle>>? grouped) {
    if (grouped == null || grouped.isEmpty) {
      return const Center(child: Text('등록된 룰북이 없습니다.'));
    }
    return ListView(
      children: [
        for (final entry in grouped.entries)
          ExpansionTile(
            title: Text(entry.key,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            children: [
              for (final article in entry.value)
                ListTile(
                  title: Text(article.title),
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => DraggableScrollableSheet(
                        expand: false,
                        initialChildSize: 0.7,
                        builder: (_, scroll) => Padding(
                          padding: const EdgeInsets.all(16),
                          child: Markdown(
                            controller: scroll,
                            data: '# ${article.title}\n\n${article.body}',
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('룰북'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [Tab(text: '테니스'), Tab(text: '풋살')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [
                _categoryList(_tennisByCat),
                _categoryList(_futsalByCat),
              ],
            ),
    );
  }
}
