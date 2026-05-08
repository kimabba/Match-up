import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config.dart';
import '../../state/providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  String? _error;

  Future<void> _emailAuth() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final supa = ref.read(supabaseProvider);
      if (_signUp) {
        await supa.auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
        );
      } else {
        await supa.auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _googleSignIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final supa = ref.read(supabaseProvider);
      await supa.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.matchup.app://login-callback/',
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      'Match-up',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Text(
                    '테니스·풋살 동호인 통합 정보',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _email,
                    decoration: const InputDecoration(
                      labelText: '이메일',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    decoration: const InputDecoration(
                      labelText: '비밀번호',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _emailAuth,
                    child: Text(_signUp ? '회원가입' : '로그인'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _signUp = !_signUp),
                    child: Text(_signUp ? '이미 계정이 있어요' : '계정이 없어요. 가입하기'),
                  ),
                  const Divider(height: 32),
                  if (AppConfig.googleWebClientId.isNotEmpty ||
                      AppConfig.googleIosClientId.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _googleSignIn,
                      icon: const Icon(Icons.account_circle_outlined),
                      label: const Text('구글로 계속하기'),
                    ),
                  const SizedBox(height: 12),
                  // 카카오는 별도 SDK 통합 필요. 추후 활성화.
                  OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('카카오로 계속하기 (준비 중)'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
