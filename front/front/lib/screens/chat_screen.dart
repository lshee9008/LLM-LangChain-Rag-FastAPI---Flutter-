import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/chat_api.dart';

class ChatMessage {
  String text;
  final bool isUser;
  bool incomplete = false;
  List<Map<String, dynamic>> sources = [];
  List<String> warnings = [];

  ChatMessage(this.text, {this.isUser = false});
}

class ChelseaChatScreen extends StatefulWidget {
  final ChatApi? api;
  final String? username;
  final Future<void> Function()? onLogout;
  const ChelseaChatScreen({super.key, this.api, this.username, this.onLogout});

  @override
  State<ChelseaChatScreen> createState() => _ChelseaChatScreenState();
}

class _ChelseaChatScreenState extends State<ChelseaChatScreen> {
  static const blue = Color(0xFF034694);
  static const navy = Color(0xFF071C39);
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <ChatMessage>[];
  late final ChatApi _api;
  String? _sessionId;
  String _title = '새 대화';
  List<Map<String, dynamic>> _conversations = [];
  bool _historyLoading = false;
  bool _listLoading = false;
  bool _archivedView = false;
  bool get _managed => widget.username != null;
  bool _loading = false;
  int _generation = 0;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? ChatApi();
    if (_managed) {
      _restoreConversations();
    } else {
      _sessionId = newSessionId();
    }
  }

  @override
  void dispose() {
    _generation++;
    if (widget.api == null) {
      _api.dispose();
    } else {
      _api.cancel();
    }
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _newChat() {
    _generation++;
    _api.cancel();
    setState(() {
      _sessionId = _managed ? null : newSessionId();
      _title = '새 대화';
      _historyLoading = false;
      _messages.clear();
      _loading = false;
      _status = '';
      _controller.clear();
    });
  }

  void _stop() {
    _generation++;
    _api.cancel();
    setState(() {
      _loading = false;
      _status = '';
      final message = _messages.last;
      message.incomplete = true;
      if (message.text.isEmpty) message.text = '답변 생성을 중지했습니다.';
      message.warnings.add('중지된 답변입니다.');
    });
  }

  Future<void> _sendMessage([String? suggested]) async {
    final text = (suggested ?? _controller.text).trim();
    if (_loading || _historyLoading || text.isEmpty) return;
    final generation = ++_generation;
    final reply = ChatMessage('');
    _controller.clear();
    setState(() {
      _messages.addAll([ChatMessage(text, isUser: true), reply]);
      _loading = true;
      _status = '블루스 봇에 연결하고 있습니다...';
    });
    _scrollToBottom();
    try {
      if (_sessionId == null) {
        final created = await _api.createConversation();
        if (!mounted || generation != _generation) return;
        _sessionId = created['id'] as String;
      }
      await for (final event in _api.send(_sessionId!, text)) {
        if (!mounted || generation != _generation) return;
        setState(() {
          switch (event.type) {
            case 'status':
              _status = event.data['message'] as String? ?? '';
            case 'token':
              reply.text += event.data['text'] as String? ?? '';
            case 'sources':
              reply.sources = (event.data['sources'] as List)
                  .cast<Map<String, dynamic>>();
              reply.warnings = (event.data['warnings'] as List).cast<String>();
            case 'done':
              reply.text = event.data['answer'] as String;
              reply.sources = (event.data['sources'] as List)
                  .cast<Map<String, dynamic>>();
              reply.warnings = (event.data['warnings'] as List).cast<String>();
          }
        });
        _scrollToBottom();
      }
      if (_managed && mounted && generation == _generation) {
        await _refreshConversations();
      }
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        reply.incomplete = true;
        reply.warnings.add(
          error is ChatApiException
              ? error.message
              : '서버에 연결할 수 없습니다. 연결 상태와 서버 주소를 확인해 주세요.',
        );
        if (reply.text.isEmpty) reply.text = '답변을 완료하지 못했습니다.';
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _status = '';
        });
      }
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error is ChatApiException
              ? error.message
              : '대화를 불러오지 못했습니다. 다시 시도해 주세요.',
        ),
      ),
    );
  }

  Future<void> _restoreConversations() async {
    final generation = _generation;
    setState(() {
      _historyLoading = true;
    });
    try {
      final conversations = await _api.conversations();
      if (!mounted || generation != _generation) return;
      setState(() {
        _conversations = conversations;
      });
      if (conversations.isNotEmpty) {
        await _openConversation(conversations.first['id'] as String);
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _historyLoading = false;
        });
      }
    }
  }

  Future<void> _refreshConversations() async {
    final archived = _archivedView;
    setState(() {
      _listLoading = true;
    });
    try {
      final conversations = await _api.conversations(archived: archived);
      if (mounted && archived == _archivedView) {
        setState(() {
          _conversations = conversations;
          for (final conversation in conversations) {
            if (conversation['id'] == _sessionId) {
              _title = conversation['title'] as String;
            }
          }
        });
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() {
          _listLoading = false;
        });
      }
    }
  }

  Future<void> _openConversation(String id) async {
    final generation = ++_generation;
    _api.cancel();
    setState(() {
      _loading = false;
      _historyLoading = true;
      _status = '';
    });
    try {
      final detail = await _api.conversation(id);
      if (!mounted || generation != _generation) return;
      final messages = <ChatMessage>[];
      for (final turn in detail['turns'] as List) {
        messages.add(ChatMessage(turn['question'] as String, isUser: true));
        messages.add(
          ChatMessage(turn['answer'] as String)
            ..sources = (turn['sources'] as List).cast<Map<String, dynamic>>()
            ..warnings = (turn['warnings'] as List).cast<String>(),
        );
      }
      setState(() {
        _sessionId = id;
        _title = detail['title'] as String;
        _messages
          ..clear()
          ..addAll(messages);
        _controller.clear();
      });
      _scrollToBottom();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _historyLoading = false;
        });
      }
    }
  }

  Future<void> _renameConversation(Map<String, dynamic> conversation) async {
    var edited = conversation['title'] as String;
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('대화 이름 바꾸기'),
        content: TextFormField(
          key: const Key('conversation-title-input'),
          initialValue: edited,
          onChanged: (value) {
            edited = value;
          },
          maxLength: 80,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              if (edited.trim().isNotEmpty) {
                Navigator.pop(context, edited.trim());
              }
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (title == null || !mounted) return;
    try {
      await _api.renameConversation(conversation['id'] as String, title);
      if (!mounted) return;
      if (_sessionId == conversation['id']) {
        setState(() {
          _title = title;
        });
      }
      await _refreshConversations();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _archiveConversation(Map<String, dynamic> conversation) async {
    final archived = !_archivedView;
    try {
      await _api.archiveConversation(conversation['id'] as String, archived);
      if (!mounted) return;
      if (archived && _sessionId == conversation['id']) _newChat();
      await _refreshConversations();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              archived ? '대화를 보관했습니다. 보관함에서 복원할 수 있어요.' : '대화를 복원했습니다.',
            ),
          ),
        );
      }
    } catch (error) {
      _showError(error);
    }
  }

  Widget _historyDrawer() => Drawer(
    child: SafeArea(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(widget.username!),
            subtitle: const Text('내 대화'),
            trailing: IconButton(
              tooltip: '로그아웃',
              onPressed: () {
                Navigator.pop(context);
                widget.onLogout?.call();
              },
              icon: const Icon(Icons.logout),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.add_comment_outlined),
            title: const Text('새 대화'),
            onTap: () {
              Navigator.pop(context);
              _newChat();
            },
          ),
          SwitchListTile(
            title: const Text('보관한 대화'),
            value: _archivedView,
            onChanged: _listLoading
                ? null
                : (value) {
                    setState(() {
                      _archivedView = value;
                    });
                    _refreshConversations();
                  },
          ),
          if (_listLoading) const LinearProgressIndicator(),
          Expanded(
            child: _conversations.isEmpty
                ? const Center(child: Text('아직 대화가 없습니다.'))
                : ListView.builder(
                    itemCount: _conversations.length,
                    itemBuilder: (context, index) {
                      final conversation = _conversations[index];
                      return ListTile(
                        selected: _sessionId == conversation['id'],
                        title: Text(
                          conversation['title'] as String,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: _archivedView
                            ? null
                            : () {
                                Navigator.pop(context);
                                _openConversation(conversation['id'] as String);
                              },
                        trailing: PopupMenuButton<String>(
                          tooltip: '대화 관리',
                          onSelected: (value) {
                            if (value == 'rename') {
                              _renameConversation(conversation);
                            } else {
                              _archiveConversation(conversation);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'rename',
                              child: Text('이름 바꾸기'),
                            ),
                            PopupMenuItem(
                              value: 'archive',
                              child: Text(_archivedView ? '복원하기' : '보관하기'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      drawer: _managed ? _historyDrawer() : null,
      appBar: AppBar(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        leading: _managed
            ? Builder(
                builder: (context) => IconButton(
                  tooltip: '내 대화',
                  onPressed: () {
                    _refreshConversations();
                    Scaffold.of(context).openDrawer();
                  },
                  icon: const Icon(Icons.history),
                ),
              )
            : null,
        title: const Row(
          children: [
            Icon(Icons.sports_soccer, color: Color(0xFFE9C66B)),
            SizedBox(width: 10),
            Flexible(
              child: Text(
                'BLUES BOT',
                style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _newChat,
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: '새 대화',
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_managed && _sessionId != null)
                        Text(
                          _title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      const Text(
                        '첼시 팬을 위한 비공식 AI · 최신 정보는 출처와 함께 확인하세요',
                        style: TextStyle(
                          color: Color(0xFF4D5E75),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _historyLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _messages.isEmpty
                      ? _welcome()
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) =>
                              _bubble(_messages[index]),
                        ),
                ),
                if (_loading)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _status,
                            style: const TextStyle(fontSize: 12, color: blue),
                          ),
                        ),
                      ],
                    ),
                  ),
                _composer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcome() => SingleChildScrollView(
    padding: const EdgeInsets.all(28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 36),
        const Icon(Icons.shield_outlined, color: blue, size: 44),
        const SizedBox(height: 24),
        const Text(
          '오늘도, 첼시 이야기.',
          style: TextStyle(
            color: navy,
            fontSize: 32,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '구단의 역사부터 최신 소식까지.\n궁금한 내용을 물어보면 근거를 찾아 답해드릴게요.',
          style: TextStyle(fontSize: 16, height: 1.7, color: Color(0xFF52647A)),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final text in [
              '첼시 최근 5경기 결과 알려줘',
              '콜 파머 최근 경기 소식 알려줘',
              '프리미어리그 순위 알려줘',
              '스탬포드 브릿지에 대해 알려줘',
            ])
              ActionChip(
                label: Text(text),
                onPressed: () => _sendMessage(text),
                backgroundColor: Colors.white,
              ),
          ],
        ),
        const SizedBox(height: 32),
        const Text(
          'KEEP THE BLUE FLAG FLYING HIGH',
          style: TextStyle(fontSize: 10, letterSpacing: 2, color: blue),
        ),
      ],
    ),
  );

  Widget _composer() => Container(
    padding: const EdgeInsets.all(16),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: Color(0xFFE1E7F0))),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            key: const Key('question-input'),
            controller: _controller,
            minLines: 1,
            maxLines: 4,
            maxLength: 2000,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _sendMessage(),
            decoration: InputDecoration(
              hintText: '첼시에 대해 질문하세요...',
              counterText: '',
              filled: true,
              fillColor: const Color(0xFFF3F6FB),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filled(
          tooltip: _loading ? '답변 중지' : '질문 보내기',
          style: IconButton.styleFrom(backgroundColor: blue),
          onPressed: _loading ? _stop : () => _sendMessage(),
          icon: Icon(
            _loading ? Icons.stop_rounded : Icons.arrow_upward_rounded,
          ),
        ),
      ],
    ),
  );

  Widget _bubble(ChatMessage message) => Align(
    alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 720),
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: message.isUser ? blue : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: message.incomplete
            ? Border.all(color: Colors.orange.shade300)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'BLUES BOT',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  color: blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          SelectableText(
            message.text.isEmpty ? '근거를 확인하고 있습니다...' : message.text,
            style: TextStyle(
              color: message.isUser ? Colors.white : navy,
              height: 1.7,
              fontSize: 15,
            ),
          ),
          for (final warning in message.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                warning,
                style: const TextStyle(
                  color: Color(0xFF8A4B00),
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          if (message.sources.isNotEmpty)
            Material(
              color: Colors.transparent,
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  '참고한 출처 ${message.sources.length}개',
                  style: const TextStyle(fontSize: 12, color: blue),
                ),
                children: [
                  for (final source in message.sources) _source(source),
                ],
              ),
            ),
          if (!message.isUser && message.text.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: '답변 복사',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: message.text));
                },
                icon: const Icon(Icons.copy_outlined, size: 16, color: blue),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _source(Map<String, dynamic> source) {
    final date = DateTime.tryParse(source['retrieved_at'] as String? ?? '')
        ?.toLocal();
    final checked = date == null
        ? ''
        : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6FB),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '[${source['id']}] ${source['title']}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '조회 $checked${source['cached'] == true ? ' · 캐시된 결과' : ''}',
            style: const TextStyle(fontSize: 10, color: Color(0xFF52647A)),
          ),
          if (source['published_at'] != null)
            Text(
              '발행 ${source['published_at']}',
              style: const TextStyle(fontSize: 10),
            ),
          if (source['url'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SelectableText(
                source['url'] as String,
                style: const TextStyle(fontSize: 11, color: blue),
              ),
            ),
        ],
      ),
    );
  }
}
