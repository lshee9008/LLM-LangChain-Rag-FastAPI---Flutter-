import 'package:flutter/material.dart';

import '../services/chat_api.dart';
import 'chat_screen.dart';

class AuthGate extends StatefulWidget {
  final ChatApi? api;
  const AuthGate({super.key, this.api});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final ChatApi _api;
  Map<String, dynamic>? _user;
  bool _checking = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? ChatApi();
    _restore();
  }

  Future<void> _restore() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final user = await _api.currentUser();
      if (mounted) {
        setState(() {
          _user = user;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '서버에 연결할 수 없습니다. 잠시 후 다시 시도해 주세요.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _checking = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    try {
      await _api.logout();
      if (mounted) {
        setState(() {
          _user = null;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ChatApiException
                  ? error.message
                  : '로그아웃하지 못했습니다. 다시 시도해 주세요.',
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!),
              const SizedBox(height: 16),
              FilledButton(onPressed: _restore, child: const Text('다시 연결')),
            ],
          ),
        ),
      );
    }
    if (_user != null) {
      return ChelseaChatScreen(
        key: ValueKey(_user!['id']),
        api: _api,
        username: _user!['username'] as String,
        onLogout: _logout,
      );
    }
    return LoginScreen(
      api: _api,
      onAuthenticated: (user) {
        setState(() {
          _user = user;
        });
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  final ChatApi api;
  final ValueChanged<Map<String, dynamic>> onAuthenticated;
  const LoginScreen({
    super.key,
    required this.api,
    required this.onAuthenticated,
  });
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await widget.api.authenticate(
        _username.text.trim(),
        _password.text,
        register: _register,
      );
      if (mounted) {
        _password.clear();
        widget.onAuthenticated(user);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is ChatApiException
              ? error.message
              : '서버에 연결하지 못했습니다. 다시 시도해 주세요.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF3F6FB),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        size: 48,
                        color: Color(0xFF034694),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'BLUES BOT',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _register
                            ? '내 대화를 이어갈 계정을 만들어보세요.'
                            : '다시 만나 반가워요.\n로그인하고 첼시 이야기를 이어가세요.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(height: 1.6),
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        key: const Key('username-input'),
                        controller: _username,
                        enabled: !_busy,
                        autofillHints: const [AutofillHints.username],
                        maxLength: 32,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '아이디',
                          helperText: '영문·숫자·밑줄 3~32자',
                          counterText: '',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            RegExp(r'^[a-zA-Z0-9_]{3,32}$')
                                .hasMatch(value?.trim() ?? '')
                            ? null
                            : '아이디 형식을 확인해 주세요.',
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        key: const Key('password-input'),
                        controller: _password,
                        enabled: !_busy,
                        obscureText: true,
                        autofillHints: [
                          _register
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        maxLength: 128,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          labelText: '비밀번호',
                          helperText: '10자 이상',
                          counterText: '',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => (value?.length ?? 0) >= 10
                            ? null
                            : '비밀번호는 10자 이상 입력해 주세요.',
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _busy
                                ? '연결 중...'
                                : _register
                                ? '가입하고 시작하기'
                                : '로그인',
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () {
                                setState(() {
                                  _register = !_register;
                                  _error = null;
                                });
                              },
                        child: Text(
                          _register ? '이미 계정이 있나요? 로그인' : '처음 오셨나요? 회원가입',
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '첼시 팬을 위한 비공식 AI',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
