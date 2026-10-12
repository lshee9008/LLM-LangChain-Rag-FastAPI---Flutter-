import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:front/services/chat_api.dart';
import 'package:http/http.dart' as http;

class StreamingClient extends http.BaseClient {
  final Stream<List<int>> bytes;
  final int status;
  final String contentType;
  StreamingClient(
    this.bytes, {
    this.status = 200,
    this.contentType = 'text/event-stream',
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        bytes,
        status,
        headers: {'content-type': contentType},
      );
}

void main() {
  test(
    'decodes split Korean UTF-8 bytes, CRLF, heartbeat and multiline JSON',
    () async {
      final input = utf8.encode(
        ': ping\r\n\r\nevent: token\r\ndata: {\r\ndata: "text": "첼시💙"}\r\n\r\nevent: done\ndata: {"answer":"끝"}\n\n',
      );
      final events = await decodeEvents(
        Stream.fromIterable(input.map((b) => [b])),
      ).toList();
      expect(events.map((e) => e.type), ['token', 'done']);
      expect(events.first.data['text'], '첼시💙');
    },
  );

  test('returns tokens before response is complete', () async {
    final api = ChatApi(
      client: StreamingClient(
        Stream.fromIterable([
          utf8.encode('event: token\ndata: {"text":"첼시"}\n\n'),
          utf8.encode('event: done\ndata: {"answer":"첼시"}\n\n'),
        ]),
      ),
    );
    expect(await api.send('session_001', 'hi').map((e) => e.type).toList(), [
      'token',
      'done',
    ]);
    api.dispose();
  });

  test('rejects truncated SSE without done', () async {
    final api = ChatApi(
      client: StreamingClient(
        Stream.value(utf8.encode('event: token\ndata: {"text":"일부"}\n\n')),
      ),
    );
    await expectLater(
      api.send('session_001', 'hi').toList(),
      throwsA(isA<ChatApiException>()),
    );
    api.dispose();
  });

  test('exposes safe server errors and validates response format', () async {
    for (final client in [
      StreamingClient(
        Stream.value(utf8.encode('{"detail":"이미 답변 중인 대화입니다."}')),
        status: 409,
        contentType: 'application/json',
      ),
      StreamingClient(
        Stream.value(
          utf8.encode('event: error\ndata: {"message":"조회 실패"}\n\n'),
        ),
      ),
      StreamingClient(const Stream.empty(), contentType: 'text/html'),
    ]) {
      final api = ChatApi(client: client);
      await expectLater(
        api.send('session_001', 'hi').toList(),
        throwsA(isA<ChatApiException>()),
      );
      api.dispose();
    }
  });

  test('session identifiers are distinct opaque values', () {
    final first = newSessionId();
    expect(first, matches(RegExp(r'^[a-f0-9]{48}$')));
    expect(newSessionId(), isNot(first));
  });
}
