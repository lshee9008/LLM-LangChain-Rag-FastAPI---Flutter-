import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/chat_api.dart';
import '../theme/blues_theme.dart';
import '../widgets/brand.dart';
import '../widgets/chat_composer.dart';
import '../widgets/conversation_sidebar.dart';
import '../widgets/message_card.dart';
import '../widgets/welcome_panel.dart';

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
  final _scaffold = GlobalKey<ScaffoldState>();
  final _controller = TextEditingController();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <ChatMessage>[];
  late final ChatApi _api;
  String? _sessionId;
  String _title = '새 대화';
  List<Map<String, dynamic>> _conversations = [];
  bool _historyLoading = false;
  bool _listLoading = false;
  bool _archivedView = false;
  bool _archivedSelection = false;
  bool _pinnedOnly = false;
  bool _followTail = true;
  int _listRequest = 0;
  Timer? _searchDebounce;
  bool get _managed => widget.username != null;
  bool _loading = false;
  int _generation = 0;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? ChatApi();
    _scroll.addListener(_onScroll);
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
    _searchDebounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final follow = _scroll.position.extentAfter < 100;
    if (follow != _followTail) setState(() => _followTail = follow);
  }

  void _scrollToBottom({bool force = false}) {
    if (force) _followTail = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients && _followTail) {
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
      _archivedSelection = false;
      _followTail = true;
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
    if (_loading || _historyLoading || _archivedSelection || text.isEmpty) {
      return;
    }
    final generation = ++_generation;
    final reply = ChatMessage('');
    _controller.clear();
    setState(() {
      _messages.addAll([ChatMessage(text, isUser: true), reply]);
      _loading = true;
      _status = '블루스 봇에 연결하고 있습니다...';
    });
    _scrollToBottom(force: true);
    try {
      if (_sessionId == null) {
        final created = await _api.createConversation();
        if (!mounted || generation != _generation) return;
        _sessionId = created['id'] as String;
        _title = text.length > 40 ? text.substring(0, 40) : text;
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
    final request = ++_listRequest;
    setState(() {
      _historyLoading = true;
    });
    try {
      final conversations = await _api.conversations();
      if (!mounted || generation != _generation || request != _listRequest) {
        return;
      }
      setState(() {
        _conversations = conversations;
      });
      if (conversations.isNotEmpty) {
        // Pinning changes list order, but restoration still opens the latest chat.
        final latest = conversations.reduce(
          (a, b) =>
              ((a['updated_at'] as num?) ?? 0) >=
                  ((b['updated_at'] as num?) ?? 0)
              ? a
              : b,
        );
        await _openConversation(latest['id'] as String);
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
    final request = ++_listRequest;
    setState(() {
      _listLoading = true;
    });
    try {
      final conversations = await _api.conversations(
        archived: archived,
        query: _search.text.trim(),
        pinnedOnly: _pinnedOnly,
      );
      if (mounted && request == _listRequest) {
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
      if (request == _listRequest) _showError(error);
    } finally {
      if (mounted && request == _listRequest) {
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
        _archivedSelection = detail['archived'] == true;
        _messages
          ..clear()
          ..addAll(messages);
        _controller.clear();
      });
      _scrollToBottom(force: true);
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
    final archived = conversation['archived'] != true;
    try {
      await _api.archiveConversation(conversation['id'] as String, archived);
      if (!mounted) return;
      if (archived && _sessionId == conversation['id']) _newChat();
      if (!archived && _sessionId == conversation['id']) {
        setState(() => _archivedSelection = false);
      }
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

  void _searchChanged(String value) {
    _searchDebounce?.cancel();
    _listRequest++; // Immediately invalidate any previous response.
    setState(() {
      _listLoading = true;
    });
    _searchDebounce = Timer(
      const Duration(milliseconds: 250),
      _refreshConversations,
    );
  }

  void _changeView(bool archived) {
    setState(() {
      _archivedView = archived;
    });
    _refreshConversations();
  }

  Future<void> _pinConversation(Map<String, dynamic> conversation) async {
    try {
      await _api.pinConversation(
        conversation['id'] as String,
        conversation['pinned'] != true,
      );
      if (mounted) await _refreshConversations();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _copyConversation() async {
    final content = StringBuffer('# $_title\n\n');
    for (final message in _messages) {
      content.writeln(
        '## ${message.isUser ? '나' : 'BLUES BOT'}\n\n${message.text}\n',
      );
      for (final warning in message.warnings) {
        content.writeln('> $warning\n');
      }
      for (final source in message.sources) {
        final uri = safeWebUri(source['url'] as String?);
        content.writeln(
          '- [${source['id']}] ${source['title']}${uri == null ? '' : ' · $uri'}',
        );
      }
      content.writeln();
    }
    await Clipboard.setData(ClipboardData(text: content.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('출처를 포함한 대화를 복사했습니다.')));
    }
  }

  void _closeDrawer() {
    if (_scaffold.currentState?.isDrawerOpen == true) {
      Navigator.of(context).pop();
    }
  }

  Widget _sidebar() => ConversationSidebar(
    username: widget.username!,
    selectedId: _sessionId,
    conversations: _conversations,
    loading: _listLoading,
    archived: _archivedView,
    pinnedOnly: _pinnedOnly,
    searchController: _search,
    onSearch: _searchChanged,
    onNew: () {
      _closeDrawer();
      _newChat();
    },
    onOpen: (id) {
      _closeDrawer();
      _openConversation(id);
    },
    onArchiveView: _changeView,
    onPinnedView: () {
      setState(() => _pinnedOnly = !_pinnedOnly);
      _refreshConversations();
    },
    onRename: _renameConversation,
    onArchive: _archiveConversation,
    onPin: _pinConversation,
    onLogout: () {
      _closeDrawer();
      widget.onLogout?.call();
    },
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = _managed && constraints.maxWidth >= 1000;
      return Scaffold(
        key: _scaffold,
        drawer: _managed && !wide
            ? Drawer(width: 300, child: _sidebar())
            : null,
        body: SafeArea(
          child: Row(
            children: [
              if (wide) SizedBox(width: 264, child: _sidebar()),
              Expanded(
                child: Column(
                  children: [
                    _header(wide),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 960),
                          child: Column(
                            children: [
                              Expanded(
                                child: _historyLoading
                                    ? const Center(
                                        child: CircularProgressIndicator(),
                                      )
                                    : _messages.isEmpty
                                    ? WelcomePanel(onQuestion: _sendMessage)
                                    : Stack(
                                        children: [
                                          ListView.builder(
                                            controller: _scroll,
                                            padding: EdgeInsets.fromLTRB(
                                              constraints.maxWidth < 600
                                                  ? 16
                                                  : 32,
                                              12,
                                              constraints.maxWidth < 600
                                                  ? 16
                                                  : 32,
                                              24,
                                            ),
                                            itemCount: _messages.length,
                                            itemBuilder: (context, index) {
                                              final message = _messages[index];
                                              return MessageCard(
                                                key: ObjectKey(message),
                                                text: message.text,
                                                isUser: message.isUser,
                                                incomplete: message.incomplete,
                                                generating:
                                                    _loading &&
                                                    index ==
                                                        _messages.length - 1,
                                                sources: message.sources,
                                                warnings: message.warnings,
                                              );
                                            },
                                          ),
                                          if (!_followTail)
                                            Positioned(
                                              bottom: 12,
                                              right: 24,
                                              child: FilledButton.icon(
                                                onPressed: () {
                                                  setState(() {});
                                                  _scrollToBottom(force: true);
                                                },
                                                icon: const Icon(
                                                  Icons.arrow_downward,
                                                  size: 16,
                                                ),
                                                label: const Text('최신 답변'),
                                                style: FilledButton.styleFrom(
                                                  backgroundColor:
                                                      BluesColors.navy,
                                                  foregroundColor: Colors.white,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                              ),
                              if (_loading)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 32,
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _status,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: BluesColors.blue,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (_archivedSelection)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    8,
                                    20,
                                    16,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: BluesColors.paleBlue,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Row(
                                      children: [
                                        const Expanded(
                                          child: Text(
                                            '보관한 대화입니다.',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              _archiveConversation({
                                                'id': _sessionId,
                                                'archived': true,
                                              }),
                                          child: const Text('복원하고 이어가기'),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else
                                ChatComposer(
                                  controller: _controller,
                                  loading: _loading,
                                  disabled: _historyLoading,
                                  onSend: _sendMessage,
                                  onStop: _stop,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _header(bool wide) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: BluesColors.line)),
    ),
    child: Row(
      children: [
        if (_managed && !wide)
          IconButton(
            tooltip: '내 대화',
            icon: const Icon(Icons.menu_rounded, size: 22),
            onPressed: () {
              _refreshConversations();
              _scaffold.currentState?.openDrawer();
            },
          ),
        if (!_managed)
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: BluesBrand(compact: true),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _sessionId != null && _messages.isNotEmpty ? _title : '팬 라운지',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  color: BluesColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                '우리의 모든 첼시 이야기',
                style: TextStyle(fontSize: 10, color: BluesColors.muted),
              ),
            ],
          ),
        ),
        if (_messages.isNotEmpty)
          IconButton(
            tooltip: '대화 복사',
            onPressed: _loading || _historyLoading ? null : _copyConversation,
            icon: const Icon(
              Icons.ios_share_outlined,
              size: 20,
              color: BluesColors.muted,
            ),
          ),
        IconButton(
          tooltip: '새 대화',
          onPressed: _newChat,
          icon: const Icon(
            Icons.edit_square,
            size: 21,
            color: BluesColors.blue,
          ),
        ),
      ],
    ),
  );
}
