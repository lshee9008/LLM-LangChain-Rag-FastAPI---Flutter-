import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'dart:convert';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RAG 실습',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  String _answer = "궁금한 기술(Flutter, LangChain 등)을 질문해보세요.";
  bool _isLoading = false;

  Future<void> _askQuestion() async {
    final query = _controller.text;
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _answer = "답변을 생성 중입니다...";
    });

    try {
      // Android 에뮬레이터는 10.0.2.2, iOS 시뮬레이터/웹은 localhost(127.0.0.1)를 사용합니다.
      final url = Uri.parse('http://localhost:8000/ask');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'query': query}),
      );

      if (response.statusCode == 200) {
        // 한글 깨짐 방지를 위해 utf8.decode 사용
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() => _answer = data['answer']);
      } else {
        setState(() => _answer = "오류 발생: \${response.statusCode}");
      }
    } catch (e) {
      setState(() => _answer = "서버 통신 실패: \$e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RAG 챗봇 (FastAPI + LangChain)')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Text(_answer, style: const TextStyle(fontSize: 16)),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: '질문을 입력하세요...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _askQuestion,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('전송'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
