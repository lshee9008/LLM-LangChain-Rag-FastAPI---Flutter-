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
  const ChelseaChatScreen({super.key, this.api});

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
  String _sessionId = newSessionId();
  bool _loading = false;
  int _generation = 0;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? ChatApi();
  }

  @override
  void dispose() {
    _generation++;
    _api.dispose();
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
      _sessionId = newSessionId();
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
    if (_loading || text.isEmpty) return;
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
      await for (final event in _api.send(_sessionId, text)) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        backgroundColor: navy,
        foregroundColor: Colors.white,
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
                  child: const Text(
                    '첼시 팬을 위한 비공식 AI · 최신 정보는 출처와 함께 확인하세요',
                    style: TextStyle(color: Color(0xFF4D5E75), fontSize: 12),
                  ),
                ),
                Expanded(
                  child: _messages.isEmpty
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
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                '참고한 출처 ${message.sources.length}개',
                style: const TextStyle(fontSize: 12, color: blue),
              ),
              children: [for (final source in message.sources) _source(source)],
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
