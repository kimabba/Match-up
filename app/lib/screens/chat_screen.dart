import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/providers.dart';

class _Msg {
  final String role;
  String content;
  List<Map<String, dynamic>> citations;
  _Msg({required this.role, required this.content})
      : citations = <Map<String, dynamic>>[];
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Msg>[];
  String? _conversationId;
  bool _busy = false;

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _busy) return;
    _ctrl.clear();

    setState(() {
      _messages.add(_Msg(role: 'user', content: text));
      _messages.add(_Msg(role: 'assistant', content: ''));
      _busy = true;
    });

    final assistantIdx = _messages.length - 1;
    final api = ref.read(apiProvider);

    try {
      await for (final evt in api.chat(
        message: text,
        conversationId: _conversationId,
      )) {
        if (!mounted) return;
        switch (evt.event) {
          case 'meta':
            _conversationId = evt.data['conversation_id'] as String?;
            break;
          case 'delta':
            setState(() {
              _messages[assistantIdx].content += evt.data['text'] as String? ?? '';
            });
            _scrollToBottom();
            break;
          case 'citation':
            final items = (evt.data['items'] as List?) ?? const [];
            setState(() {
              _messages[assistantIdx].citations = [
                ..._messages[assistantIdx].citations,
                ...items.cast<Map<String, dynamic>>(),
              ];
            });
            break;
          case 'error':
            setState(() {
              _messages[assistantIdx].content +=
                  '\n\n[오류] ${evt.data['message'] ?? '알 수 없는 오류'}';
            });
            break;
        }
      }
    } catch (e) {
      setState(() {
        _messages[assistantIdx].content += '\n\n[연결 실패] $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 챗봇')),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        '내 등급으로 출전 가능한 대회나, 종목 규칙을 자유롭게 물어보세요.\n\n예) "이번 주말 광주에서 열리는 대회 알려줘"\n예) "테니스 발리 시 라인 안에 있어도 되나요?"',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _MessageBubble(msg: _messages[i]),
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      decoration: const InputDecoration(
                        hintText: '메시지를 입력하세요',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton.filled(
                    onPressed: _busy ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.msg});
  final _Msg msg;

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        child: Card(
          color: isUser
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(msg.content.isEmpty ? '…' : msg.content),
                if (msg.citations.isNotEmpty) ...[
                  const Divider(height: 16),
                  for (final c in msg.citations.take(8))
                    InkWell(
                      onTap: c['url'] != null
                          ? () => launchUrl(Uri.parse(c['url'] as String),
                              mode: LaunchMode.externalApplication)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(children: [
                          Icon(
                            c['type'] == 'web' ? Icons.link : Icons.storage,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              c['title']?.toString() ??
                                  c['url']?.toString() ??
                                  c['source']?.toString() ??
                                  '',
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
