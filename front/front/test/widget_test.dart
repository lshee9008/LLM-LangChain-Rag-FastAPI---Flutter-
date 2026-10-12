import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/main.dart';
import 'package:front/screens/chat_screen.dart';
import 'package:front/services/chat_api.dart';

class FakeApi extends ChatApi {
  final events = StreamController<ChatEvent>();
  final sessions = <String>[];
  bool cancelled = false;

  @override
  Stream<ChatEvent> send(String sessionId, String question) {
    sessions.add(sessionId);
    return events.stream;
  }

  @override
  void cancel() {
    cancelled = true;
  }

  @override
  void dispose() {
    events.close();
    super.dispose();
  }
}

void main() {
  testWidgets('shows Chelsea welcome and suggested questions', (tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('오늘도, 첼시 이야기.'), findsOneWidget);
    expect(find.text('첼시 최근 5경기 결과 알려줘'), findsOneWidget);
    expect(find.byTooltip('새 대화'), findsOneWidget);
  });

  testWidgets('renders partial tokens, completion and resets conversation', (
    tester,
  ) async {
    final api = FakeApi();
    await tester.pumpWidget(MaterialApp(home: ChelseaChatScreen(api: api)));
    await tester.enterText(find.byKey(const Key('question-input')), '홈구장 알려줘');
    await tester.tap(find.byTooltip('질문 보내기'));
    await tester.pump();
    api.events.add(const ChatEvent('token', {'text': '스탬포드 '}));
    await tester.pump();
    expect(find.text('스탬포드 '), findsOneWidget);
    expect(find.byTooltip('답변 중지'), findsOneWidget);
    api.events.add(
      const ChatEvent('done', {
        'answer': '스탬포드 브릿지 [1]',
        'sources': [],
        'warnings': [],
      }),
    );
    await api.events.close();
    await tester.pumpAndSettle();
    expect(find.text('스탬포드 브릿지 [1]'), findsOneWidget);
    await tester.tap(find.byTooltip('새 대화'));
    await tester.pumpAndSettle();
    expect(find.text('오늘도, 첼시 이야기.'), findsOneWidget);
    expect(api.cancelled, isTrue);
  });

  testWidgets('stopping marks partial reply and ignores late events', (
    tester,
  ) async {
    final api = FakeApi();
    await tester.pumpWidget(MaterialApp(home: ChelseaChatScreen(api: api)));
    await tester.enterText(find.byKey(const Key('question-input')), '최근 경기');
    await tester.tap(find.byTooltip('질문 보내기'));
    await tester.pump();
    api.events.add(const ChatEvent('token', {'text': '일부 답변'}));
    await tester.pump();
    await tester.tap(find.byTooltip('답변 중지'));
    await tester.pump();
    api.events.add(const ChatEvent('token', {'text': '늦게 온 답변'}));
    await tester.pump();
    expect(find.text('일부 답변'), findsOneWidget);
    expect(find.text('중지된 답변입니다.'), findsOneWidget);
    expect(find.textContaining('늦게 온 답변'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed stream preserves partial text and shows an error', (
    tester,
  ) async {
    final api = FakeApi();
    await tester.pumpWidget(MaterialApp(home: ChelseaChatScreen(api: api)));
    await tester.enterText(find.byKey(const Key('question-input')), '홈구장');
    await tester.tap(find.byTooltip('질문 보내기'));
    await tester.pump();
    api.events.add(const ChatEvent('token', {'text': '일부 답변'}));
    api.events.addError(const ChatApiException('연결 끊김'));
    await tester.pumpAndSettle();
    expect(find.text('일부 답변'), findsOneWidget);
    expect(find.text('연결 끊김'), findsOneWidget);
    expect(find.byTooltip('질문 보내기'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
