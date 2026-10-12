import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/screens/auth_gate.dart';
import 'package:front/screens/chat_screen.dart';
import 'package:front/services/chat_api.dart';
import 'package:front/theme/blues_theme.dart';
import 'package:front/widgets/chat_composer.dart';
import 'package:front/widgets/message_card.dart';
import 'package:front/widgets/conversation_sidebar.dart';
import 'package:front/widgets/welcome_panel.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'phase4_test.dart' show AccountApi;
import 'widget_test.dart' show FakeApi;

class SearchApi extends AccountApi {
  final pending = <String, Completer<List<Map<String, dynamic>>>>{};
  @override
  Future<List<Map<String, dynamic>>> conversations({
    bool archived = false,
    String query = '',
    bool pinnedOnly = false,
  }) {
    if (query.isEmpty) {
      return super.conversations(archived: archived, pinnedOnly: pinnedOnly);
    }
    return (pending[query] = Completer<List<Map<String, dynamic>>>()).future;
  }
}

Future<void> wideScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
    'welcome recommendations remain usable on a small screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? question;
      await tester.pumpWidget(
        MaterialApp(
          theme: bluesTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: WelcomePanel(onQuestion: (text) => question = text),
          ),
        ),
      );
      final suggestion = find.text('스탬포드 브릿지에 대해 알려줘');
      await tester.ensureVisible(suggestion);
      await tester.tap(suggestion);
      await tester.pumpAndSettle();
      expect(question, '스탬포드 브릿지에 대해 알려줘');
      expect(tester.takeException(), isNull);
    },
  );

  test('only ordinary HTTP(S) links can be opened', () {
    for (final url in [
      'javascript:alert(1)',
      'file:///etc/passwd',
      'data:text/html,x',
      '//example.com',
      'https://user:pass@example.com',
      'https://example.com/\nx',
    ]) {
      expect(safeWebUri(url), isNull);
    }
    expect(
      safeWebUri('https://www.chelseafc.com/en/news')?.host,
      'www.chelseafc.com',
    );
  });

  test('conversation search is URL encoded and pin is an authenticated API operation', () async {
    final requests = <http.Request>[];
    final api = ChatApi(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          request.method == 'GET' ? '{"conversations":[]}' : '{}',
          200,
        );
      }),
    );
    await api.conversations(query: '파머 & 100%', pinnedOnly: true);
    await api.pinConversation('owned_chat', true);
    expect(requests.first.url.queryParameters['q'], '파머 & 100%');
    expect(requests.first.url.queryParameters['pinned_only'], 'true');
    expect(requests.last.url.path, '/api/v1/conversations/owned_chat/pin');
    expect(requests.last.body, '{"pinned":true}');
    api.dispose();
  });

  testWidgets(
    'desktop keeps conversation navigation visible and favorites work',
    (tester) async {
      await wideScreen(tester);
      final api = AccountApi(signedIn: true);
      await tester.pumpWidget(
        MaterialApp(
          theme: bluesTheme(),
          home: ChelseaChatScreen(api: api, username: 'fan'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ConversationSidebar), findsOneWidget);
      expect(find.byTooltip('내 대화'), findsNothing);
      await tester.tap(find.byTooltip('대화 관리'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('즐겨찾기'));
      await tester.pumpAndSettle();
      expect(api.items.first['pinned'], isTrue);
      await tester.tap(find.byTooltip('즐겨찾기만 보기'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('전체 대화 보기'), findsOneWidget);
    },
  );

  testWidgets('latest chat restores independently from favorite ordering', (
    tester,
  ) async {
    final api = AccountApi(signedIn: true);
    api.items.first.addAll({'pinned': true, 'updated_at': 100});
    api.items.add({
      'id': 'latest_chat',
      'title': '최신 대화',
      'archived': false,
      'updated_at': 200,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ChelseaChatScreen(api: api, username: 'fan'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('최신 대화'), findsOneWidget);
  });

  testWidgets('slow previous search cannot replace the latest results', (
    tester,
  ) async {
    await wideScreen(tester);
    final api = SearchApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: bluesTheme(),
        home: ChelseaChatScreen(api: api, username: 'fan'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('conversation-search')), 'old');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const Key('conversation-search')), 'new');
    await tester.pump(const Duration(milliseconds: 300));
    api.pending['new']!.complete([
      {'id': 'new', 'title': '새 검색 결과', 'archived': false},
    ]);
    await tester.pumpAndSettle();
    api.pending['old']!.complete([
      {'id': 'old', 'title': '이전 검색 결과', 'archived': false},
    ]);
    await tester.pumpAndSettle();
    expect(find.text('새 검색 결과'), findsOneWidget);
    expect(find.text('이전 검색 결과'), findsNothing);
  });

  testWidgets('archived chats can be read and restored before continuing', (
    tester,
  ) async {
    await wideScreen(tester);
    final api = AccountApi(signedIn: true);
    api.items.first['archived'] = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: bluesTheme(),
        home: ChelseaChatScreen(api: api, username: 'fan'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('보관한 대화'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지난 경기 이야기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('question-input')), findsNothing);
    expect(find.text('스탬포드 브릿지입니다. [1]'), findsOneWidget);
    await tester.tap(find.text('복원하고 이어가기'));
    await tester.pumpAndSettle();
    expect(api.items.first['archived'], isFalse);
    expect(find.byKey(const Key('question-input')), findsOneWidget);
  });

  testWidgets('Markdown table fits a narrow screen and images never load', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: bluesTheme(),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: MessageCard(
              text: '## 경기 요약\n\n**강조**\n\n|선수|기록|설명|\n|---|---|---|\n|콜 파머|3|매우 긴 기록 내용입니다|\n\n![외부 이미지](https://example.com/tracker.png)',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('경기 요약'), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Enter sends, Shift Enter does not, active IME composition never sends',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var sent = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatComposer(
              controller: controller,
              loading: false,
              disabled: false,
              onSend: () => sent++,
              onStop: () {},
            ),
          ),
        ),
      );
      final field = find.byKey(const Key('question-input'));
      await tester.enterText(field, '첼시');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(sent, 0);
      controller.value = const TextEditingValue(
        text: '첼시',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(sent, 0);
      controller.value = const TextEditingValue(
        text: '첼시',
        selection: TextSelection.collapsed(offset: 2),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(sent, 1);
    },
  );

  testWidgets(
    'copying a conversation includes questions, answers and sources',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ChelseaChatScreen(api: AccountApi(), username: 'fan'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('대화 복사'));
      await tester.pumpAndSettle();
      expect(copied, contains('첼시 홈구장은?'));
      expect(copied, contains('스탬포드 브릿지'));
      expect(copied, contains('[1] 구단 문서'));
    },
  );

  testWidgets('reading earlier text is not interrupted by streaming tokens', (
    tester,
  ) async {
    final api = FakeApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: bluesTheme(),
        home: ChelseaChatScreen(api: api),
      ),
    );
    await tester.enterText(find.byKey(const Key('question-input')), '긴 이야기');
    await tester.pump();
    await tester.tap(find.byTooltip('질문 보내기'));
    await tester.pump();
    api.events.add(
      ChatEvent('token', {'text': List.filled(45, '첼시 이야기입니다.\n\n').join()}),
    );
    await tester.pump();
    await tester.pump();
    final list = find.byType(ListView);
    await tester.drag(list, const Offset(0, 600));
    await tester.pump(const Duration(milliseconds: 600));
    final controller = tester.widget<ListView>(list).controller!;
    final before = controller.offset;
    api.events.add(const ChatEvent('token', {'text': '\n새 토큰'}));
    await tester.pump();
    await tester.pump();
    expect(controller.offset, before);
    expect(find.text('최신 답변'), findsOneWidget);
    await tester.tap(find.text('최신 답변'));
    await tester.pump();
    await tester.pump();
    expect(controller.position.extentAfter, lessThan(2));
    await tester.pumpWidget(const SizedBox());
    await api.events.close();
  });

  testWidgets('mobile drawer and enlarged text have no overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: bluesTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: ChelseaChatScreen(api: AccountApi(), username: 'fan'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('내 대화'), findsOneWidget);
    await tester.tap(find.byTooltip('내 대화'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conversation-search')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('password visibility can be toggled without changing its value', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: bluesTheme(),
        home: LoginScreen(api: AccountApi(), onAuthenticated: (_) {}),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('password-input')),
      'a test password',
    );
    await tester.tap(find.byTooltip('비밀번호 보기'));
    await tester.pump();
    final input = tester.widget<TextFormField>(
      find.byKey(const Key('password-input')),
    );
    expect(input.controller!.text, 'a test password');
    expect(find.byTooltip('비밀번호 숨기기'), findsOneWidget);
  });
}
