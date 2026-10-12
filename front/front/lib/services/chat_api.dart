import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

class ChatEvent {
  final String type;
  final Map<String, dynamic> data;
  const ChatEvent(this.type, this.data);
}

// Decode UTF-8 before splitting SSE lines: Korean bytes can span network chunks.
Stream<ChatEvent> decodeEvents(Stream<List<int>> bytes) async* {
  var type = 'message';
  final data = <String>[];
  await for (final line
      in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (data.isNotEmpty) {
        yield ChatEvent(
          type,
          jsonDecode(data.join('\n')) as Map<String, dynamic>,
        );
      }
      type = 'message';
      data.clear();
    } else if (line.startsWith('event:')) {
      type = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      data.add(line.substring(5).replaceFirst(RegExp(r'^ '), ''));
    }
    // SSE comments (heartbeat), id and retry fields are intentionally ignored.
  }
}

String newSessionId() {
  final random = Random.secure();
  return List.generate(
    24,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class ChatApiException implements Exception {
  final String message;
  const ChatApiException(this.message);
  @override
  String toString() => message;
}

class ChatApi {
  static const defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
  final http.Client client;
  final String baseUrl;
  Completer<void>? _abort;

  ChatApi({http.Client? client, this.baseUrl = defaultBaseUrl})
    : client = client ?? http.Client();

  void cancel() {
    if (_abort case final abort? when !abort.isCompleted) {
      abort.complete();
    }
  }

  Stream<ChatEvent> send(String sessionId, String question) async* {
    final abort = Completer<void>();
    _abort = abort;
    try {
      final request =
          http.AbortableRequest(
              'POST',
              Uri.parse('$baseUrl/api/v1/chat/stream'),
              abortTrigger: abort.future,
            )
            ..headers.addAll({
              'Content-Type': 'application/json',
              'Accept': 'text/event-stream',
            })
            ..body = jsonEncode({
              'session_id': sessionId,
              'question': question,
            });
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString().timeout(
          const Duration(seconds: 10),
        );
        var message = '서버 응답 오류 (${response.statusCode})';
        try {
          final detail = (jsonDecode(body) as Map<String, dynamic>)['detail'];
          if (detail is String) message = detail;
        } on FormatException {
          // A proxy may return HTML rather than API JSON.
        }
        throw ChatApiException(message);
      }
      if (!(response.headers['content-type'] ?? '').contains(
        'text/event-stream',
      )) {
        throw const ChatApiException('서버가 스트리밍 형식으로 응답하지 않았습니다.');
      }
      var completed = false;
      await for (final event in decodeEvents(
        response.stream.timeout(const Duration(seconds: 35)),
      )) {
        if (event.type == 'error') {
          throw ChatApiException(
            event.data['message'] as String? ?? '답변 생성에 실패했습니다.',
          );
        }
        if (event.type == 'done') completed = true;
        yield event;
        if (completed) break;
      }
      if (!completed) throw const ChatApiException('연결이 끊겨 답변을 완료하지 못했습니다.');
    } on TimeoutException {
      throw const ChatApiException('서버 응답 시간이 초과되었습니다. 다시 시도해 주세요.');
    } finally {
      if (!abort.isCompleted) abort.complete();
      if (identical(_abort, abort)) _abort = null;
    }
  }

  void dispose() {
    cancel();
    client.close();
  }
}
