import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'platform_client.dart';

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
  final int? statusCode;
  const ChatApiException(this.message, {this.statusCode});
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
  String? _token;

  ChatApi({http.Client? client, this.baseUrl = defaultBaseUrl})
    : client = client ?? createPlatformClient();

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (!kIsWeb) 'X-Client-Platform': 'native',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  Future<Map<String, dynamic>> _json(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    try {
      final request = http.Request(method, Uri.parse('$baseUrl$path'))
        ..headers.addAll(_headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 20));
      final response = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 20));
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode >= 400) {
        throw ChatApiException(
          data['detail'] is String
              ? data['detail'] as String
              : '입력 내용을 확인해 주세요.',
          statusCode: response.statusCode,
        );
      }
      return data;
    } on TimeoutException {
      throw const ChatApiException('서버 응답 시간이 초과되었습니다. 다시 시도해 주세요.');
    }
  }

  Future<Map<String, dynamic>?> currentUser() async {
    try {
      return (await _json('GET', '/api/v1/auth/me'))['user']
          as Map<String, dynamic>;
    } on ChatApiException catch (error) {
      if (error.statusCode == 401) return null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> authenticate(
    String username,
    String password, {
    bool register = false,
  }) async {
    final data = await _json(
      'POST',
      '/api/v1/auth/${register ? 'register' : 'login'}',
      {'username': username, 'password': password},
    );
    _token = data['token'] as String?;
    return data['user'] as Map<String, dynamic>;
  }

  Future<void> logout() async {
    cancel();
    try {
      await _json('POST', '/api/v1/auth/logout', {});
    } on ChatApiException catch (error) {
      if (error.statusCode != 401) rethrow;
    }
    _token = null;
  }

  Future<List<Map<String, dynamic>>> conversations({
    bool archived = false,
  }) async =>
      ((await _json(
                'GET',
                '/api/v1/conversations?archived=$archived',
              ))['conversations']
              as List)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> createConversation() =>
      _json('POST', '/api/v1/conversations', {});
  Future<Map<String, dynamic>> conversation(String id) =>
      _json('GET', '/api/v1/conversations/$id');
  Future<void> renameConversation(String id, String title) async {
    await _json('PATCH', '/api/v1/conversations/$id', {'title': title});
  }

  Future<void> archiveConversation(String id, bool archived) async {
    await _json('POST', '/api/v1/conversations/$id/archive', {
      'archived': archived,
    });
  }

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
            ..headers.addAll({..._headers, 'Accept': 'text/event-stream'})
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
        throw ChatApiException(message, statusCode: response.statusCode);
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
