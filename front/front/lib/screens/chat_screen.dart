import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'dart:convert';

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

class ChelseaChatScreen extends StatefulWidget {
  const ChelseaChatScreen({super.key});

  @override
  State<ChelseaChatScreen> createState() => _ChelseaChatScreenState();
}

class _ChelseaChatScreenState extends State<ChelseaChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<ChatMessage> _messages = [];
  final String _sessionId = "user_session_chelsea_001"; // 세션 고유 ID
  bool _isLoading = false;

  // 첼시 브랜드 컬러
  static const Color chelseaBlue = Color(0xFF034694);
  static const Color chelseaGold = Color(0xFFDBA111);

  @override
  void initState() {
    super.initState();
    // 초기 웰컴 메시지
    _messages.add(
      ChatMessage(
        text: "안녕하세요! 첼시 FC 공식 AI '블루스 봇'입니다. 🦁💙\n선수단, 경기 일정, 스탬포드 브릿지에 대해 무엇이든 물어보세요!",
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    setState(() {
      _messages.add(
        ChatMessage(text: text, isUser: true, timestamp: DateTime.now()),
      );
      _isLoading = true;
    });

    try {
      // Android 시뮬레이터 기준 10.0.2.2, iOS 시뮬레이터/macOS는 127.0.0.1
      final response = await http.post(
        Uri.parse('http://127.0.0.1:8000/api/v1/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'session_id': _sessionId, 'question': text}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _messages.add(
            ChatMessage(
              text: data['answer'],
              isUser: false,
              timestamp: DateTime.now(),
            ),
          );
        });
      } else {
        _showErrorBubble("서버 응답 오류가 발생했습니다. (Code: ${response.statusCode})");
      }
    } catch (e) {
      _showErrorBubble("백엔드 서버와 통신할 수 없습니다.");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showErrorBubble(String errorMsg) {
    setState(() {
      _messages.add(
        ChatMessage(text: errorMsg, isUser: false, timestamp: DateTime.now()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: chelseaBlue,
        title: Row(
          children: const [
            Icon(Icons.sports_soccer, color: chelseaGold),
            SizedBox(width: 8),
            Text(
              'Chelsea FC Blues Bot',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // 메시지 리스트
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12.0),
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[_messages.length - 1 - index];
                return _buildChatBubble(message);
              },
            ),
          ),

          // 답변 생성 중 로딩 인디케이터
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 8.0,
                horizontal: 16.0,
              ),
              child: Row(
                children: const [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: chelseaBlue,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    "블루스 봇이 답변을 작성하고 있습니다...",
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            ),

          // 입력창
          Container(
            padding: const EdgeInsets.all(8.0),
            color: Colors.grey[100],
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: '첼시에 대해 질문하세요...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24.0)),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        fillColor: Colors.white,
                        filled: true,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: chelseaBlue,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(ChatMessage message) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4.0),
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
        decoration: BoxDecoration(
          color: message.isUser ? chelseaBlue : Colors.grey[200],
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(message.isUser ? 16 : 0),
            bottomRight: Radius.circular(message.isUser ? 0 : 16),
          ),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: message.isUser ? Colors.white : Colors.black87,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
