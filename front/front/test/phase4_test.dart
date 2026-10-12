import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/screens/auth_gate.dart';
import 'package:front/screens/chat_screen.dart';
import 'package:front/services/chat_api.dart';

class AccountApi extends ChatApi {
  bool signedIn;
  bool rejectLogin = false;
  bool? registered;
  int creates = 0;
  final items = <Map<String, dynamic>>[
    {'id': 'conversation_001', 'title': '지난 경기 이야기', 'archived': false},
  ];
  AccountApi({this.signedIn = false});

  @override
  Future<Map<String, dynamic>?> currentUser() async =>
      signedIn ? {'id': 'user_001', 'username': 'chelsea_fan'} : null;
  @override
  Future<Map<String, dynamic>> authenticate(
    String username,
    String password, {
    bool register = false,
  }) async {
    if (rejectLogin) {
      throw const ChatApiException('아이디 또는 비밀번호를 확인해 주세요.', statusCode: 401);
    }
    registered = register;
    signedIn = true;
    return {'id': 'user_001', 'username': username};
  }

  @override
  Future<void> logout() async {
    signedIn = false;
  }

  @override
  Future<List<Map<String, dynamic>>> conversations({
    bool archived = false,
    String query = '',
    bool pinnedOnly = false,
  }) async => items
      .where((item) => item['archived'] == archived)
      .where((item) => !pinnedOnly || item['pinned'] == true)
      .where((item) => (item['title'] as String).contains(query))
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
  @override
  Future<Map<String, dynamic>> conversation(String id) async => {
    ...items.firstWhere((item) => item['id'] == id),
    'turns': [
      {
        'question': '첼시 홈구장은?',
        'answer': '스탬포드 브릿지입니다. [1]',
        'sources': [
          {'id': '1', 'title': '구단 문서', 'retrieved_at': '2026-10-12T00:00:00Z'},
        ],
        'warnings': ['이전 대화에서 확인한 자료입니다.'],
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> createConversation() async {
    creates++;
    final item = {
      'id': 'new_conversation_$creates',
      'title': '새 대화',
      'archived': false,
    };
    items.add(item);
    return item;
  }

  @override
  Stream<ChatEvent> send(String sessionId, String question) async* {
    yield const ChatEvent('token', {'text': '새 답변'});
    yield const ChatEvent('done', {
      'answer': '새 답변',
      'sources': [],
      'warnings': [],
    });
  }

  @override
  Future<void> renameConversation(String id, String title) async {
    items.firstWhere((item) => item['id'] == id)['title'] = title;
  }

  @override
  Future<void> archiveConversation(String id, bool archived) async {
    items.firstWhere((item) => item['id'] == id)['archived'] = archived;
  }

  @override
  Future<void> pinConversation(String id, bool pinned) async {
    items.firstWhere((item) => item['id'] == id)['pinned'] = pinned;
  }
}

void main() {
  testWidgets('unauthenticated gate shows login and validates input locally', (
    tester,
  ) async {
    final api = AccountApi();
    await tester.pumpWidget(MaterialApp(home: AuthGate(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('로그인'), findsOneWidget);
    await tester.tap(find.text('로그인'));
    await tester.pumpAndSettle();
    expect(find.text('아이디 형식을 확인해 주세요.'), findsOneWidget);
    expect(find.text('비밀번호는 10자 이상 입력해 주세요.'), findsOneWidget);
    expect(api.signedIn, isFalse);
  });

  testWidgets(
    'registration leads to owned history and logout clears the screen',
    (tester) async {
      final api = AccountApi();
      await tester.pumpWidget(MaterialApp(home: AuthGate(api: api)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('처음 오셨나요? 회원가입'));
      await tester.enterText(
        find.byKey(const Key('username-input')),
        'chelsea_fan',
      );
      await tester.enterText(
        find.byKey(const Key('password-input')),
        'temporary-password',
      );
      await tester.tap(find.text('가입하고 시작하기'));
      await tester.pumpAndSettle();
      expect(api.registered, isTrue);
      expect(find.text('스탬포드 브릿지입니다. [1]'), findsOneWidget);
      await tester.tap(find.byTooltip('내 대화'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('로그아웃'));
      await tester.pumpAndSettle();
      expect(find.text('로그인'), findsOneWidget);
      expect(find.text('스탬포드 브릿지입니다. [1]'), findsNothing);
    },
  );

  testWidgets(
    'restored login loads the latest conversation with its evidence',
    (tester) async {
      final api = AccountApi(signedIn: true);
      await tester.pumpWidget(MaterialApp(home: AuthGate(api: api)));
      await tester.pumpAndSettle();
      expect(find.text('지난 경기 이야기'), findsOneWidget);
      expect(find.text('참고한 출처 1개'), findsOneWidget);
      expect(find.text('이전 대화에서 확인한 자료입니다.'), findsOneWidget);
      await tester.tap(find.text('참고한 출처 1개'));
      await tester.pumpAndSettle();
      expect(find.text('[1] 구단 문서'), findsOneWidget);
    },
  );

  testWidgets(
    'new conversation is created on first send and never on empty navigation',
    (tester) async {
      final api = AccountApi(signedIn: true);
      await tester.pumpWidget(
        MaterialApp(
          home: ChelseaChatScreen(api: api, username: 'chelsea_fan'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('새 대화'));
      await tester.pumpAndSettle();
      expect(api.creates, 0);
      await tester.enterText(find.byKey(const Key('question-input')), '새 질문');
      await tester.pump();
      await tester.tap(find.byTooltip('질문 보내기'));
      await tester.pumpAndSettle();
      expect(api.creates, 1);
      expect(find.text('새 답변'), findsOneWidget);
    },
  );

  testWidgets(
    'conversation title changes and archived conversations can be restored',
    (tester) async {
      final api = AccountApi(signedIn: true);
      await tester.pumpWidget(
        MaterialApp(
          home: ChelseaChatScreen(api: api, username: 'chelsea_fan'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('내 대화'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('대화 관리'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('이름 바꾸기'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('conversation-title-input')),
        '나의 첼시 기록',
      );
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(api.items.first['title'], '나의 첼시 기록');
      await tester.tap(find.byTooltip('대화 관리'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('보관하기'));
      await tester.pumpAndSettle();
      expect(api.items.first['archived'], isTrue);
      await tester.tap(find.text('보관한 대화'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('대화 관리'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('복원하기'));
      await tester.pumpAndSettle();
      expect(api.items.first['archived'], isFalse);
    },
  );

  testWidgets('failed login stays on login and displays the server message', (
    tester,
  ) async {
    final api = AccountApi()..rejectLogin = true;
    await tester.pumpWidget(MaterialApp(home: AuthGate(api: api)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('username-input')),
      'chelsea_fan',
    );
    await tester.enterText(
      find.byKey(const Key('password-input')),
      'wrong-password',
    );
    await tester.tap(find.text('로그인'));
    await tester.pumpAndSettle();
    expect(find.text('아이디 또는 비밀번호를 확인해 주세요.'), findsOneWidget);
    expect(find.byTooltip('내 대화'), findsNothing);
  });
}
