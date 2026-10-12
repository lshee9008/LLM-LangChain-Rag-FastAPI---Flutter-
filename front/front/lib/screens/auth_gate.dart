import 'package:flutter/material.dart';

import '../services/chat_api.dart';
import '../theme/blues_theme.dart';
import '../widgets/brand.dart';
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
  bool _hidePassword = true;
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
    body: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 960;
        return SafeArea(
          child: Row(
            children: [
              if (wide) Expanded(flex: 5, child: _story()),
              Expanded(
                flex: 6,
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(wide ? 48 : 24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 380),
                      child: Form(
                        key: _form,
                        child: AutofillGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!wide) ...[
                                const BluesBrand(compact: true),
                                const SizedBox(height: 28),
                              ],
                              Text(
                                _register
                                    ? 'JOIN THE BLUE SIDE'
                                    : 'WELCOME BACK',
                                style: const TextStyle(
                                  color: BluesColors.blue,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _register ? '나만의 블루 스페이스.' : '첼시 이야기를 이어가세요.',
                                style: const TextStyle(
                                  color: BluesColors.ink,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _register
                                    ? '계정을 만들고 좋아하는 이야기를 모아보세요.'
                                    : '저장한 대화와 새로운 이야기가 기다리고 있어요.',
                                style: const TextStyle(
                                  color: BluesColors.muted,
                                  fontSize: 12,
                                  height: 1.7,
                                ),
                              ),
                              const SizedBox(height: 24),
                              TextFormField(
                                key: const Key('username-input'),
                                controller: _username,
                                enabled: !_busy,
                                autofillHints: const [AutofillHints.username],
                                autocorrect: false,
                                enableSuggestions: false,
                                maxLength: 32,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: '아이디',
                                  helperText: '영문·숫자·밑줄 3~32자',
                                  counterText: '',
                                  prefixIcon: Icon(
                                    Icons.person_outline_rounded,
                                    size: 20,
                                  ),
                                ),
                                validator: (value) =>
                                    RegExp(r'^[a-zA-Z0-9_]{3,32}$')
                                        .hasMatch(value?.trim() ?? '')
                                    ? null
                                    : '아이디 형식을 확인해 주세요.',
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                key: const Key('password-input'),
                                controller: _password,
                                enabled: !_busy,
                                obscureText: _hidePassword,
                                autocorrect: false,
                                enableSuggestions: false,
                                autofillHints: [
                                  _register
                                      ? AutofillHints.newPassword
                                      : AutofillHints.password,
                                ],
                                maxLength: 128,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                decoration: InputDecoration(
                                  labelText: '비밀번호',
                                  helperText: '10자 이상',
                                  counterText: '',
                                  prefixIcon: const Icon(
                                    Icons.lock_outline_rounded,
                                    size: 20,
                                  ),
                                  suffixIcon: IconButton(
                                    tooltip: _hidePassword
                                        ? '비밀번호 보기'
                                        : '비밀번호 숨기기',
                                    onPressed: () => setState(
                                      () => _hidePassword = !_hidePassword,
                                    ),
                                    icon: Icon(
                                      _hidePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      size: 19,
                                    ),
                                  ),
                                ),
                                validator: (value) => (value?.length ?? 0) >= 10
                                    ? null
                                    : '비밀번호는 10자 이상 입력해 주세요.',
                              ),
                              if (_error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      _error!,
                                      style: const TextStyle(
                                        color: Color(0xFFAE273A),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 22),
                              FilledButton(
                                onPressed: _busy ? null : _submit,
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Text(
                                    _busy
                                        ? '연결 중...'
                                        : _register
                                        ? '가입하고 시작하기'
                                        : '로그인',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
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
                                  _register
                                      ? '이미 계정이 있나요? 로그인'
                                      : '처음 오셨나요? 회원가입',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                '첼시 팬을 위한 비공식 AI',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: BluesColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _story() => Container(
    color: BluesColors.navy,
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BluesBrand(light: true),
                  const Spacer(),
                  const SizedBox(height: 36),
                  const Text(
                    'SAME CLUB.\nNEW CONVERSATIONS.',
                    style: TextStyle(
                      color: Color(0xFFDFE8FF),
                      fontSize: 11,
                      height: 1.8,
                      letterSpacing: 2.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '경기가 끝나도,\n우리의 이야기는 계속.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      height: 1.45,
                      letterSpacing: -1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 190,
                    child: Row(
                      children: [
                        const Expanded(
                          child: PitchArt(color: Color(0xFF5879C0)),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _feature(Icons.forum_outlined, '대화는 이어서'),
                              const SizedBox(height: 24),
                              _feature(Icons.bookmark_border, '좋아하는 이야기는 가까이'),
                              const SizedBox(height: 24),
                              _feature(
                                Icons.library_books_outlined,
                                '정보는 출처와 함께',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 36),
                  const Spacer(),
                  const Text(
                    'KEEP THE BLUE FLAG FLYING HIGH',
                    style: TextStyle(
                      color: BluesColors.gold,
                      fontSize: 9,
                      letterSpacing: 1.8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _feature(IconData icon, String text) => Row(
    children: [
      Icon(icon, size: 17, color: const Color(0xFFAEC2F1)),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(color: Color(0xFFCCD8F2), fontSize: 11),
        ),
      ),
    ],
  );
}
