# Blues Bot Flutter 앱

반응형 팬 라운지, 회원가입·로그인, 대화 검색·즐겨찾기·보관, Markdown 스트리밍 답변과 출처 링크를 지원하는 첼시 팬 챗봇 화면입니다.

```sh
flutter pub get
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 5173 --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Flutter 3.47.2 / Dart 3.13.2에서 검증했습니다. 서버 주소·플랫폼별 설정·테스트는 [프로젝트 실행 안내](../../README.md)를 참고하세요.

디자인 토큰은 `lib/theme/blues_theme.dart`, 화면 구성요소는 `lib/widgets/`에서 관리합니다. 로그인 화면은 960px, 채팅의 고정 사이드바는 1,000px 이상에서 넓은 화면 배치를 사용합니다. 모바일에서는 메뉴로 대화 목록을 엽니다.

답변은 `flutter_markdown_plus`로 표시합니다. Markdown의 이미지는 텍스트 대체만 표시하고 자동으로 내려받지 않습니다. `url_launcher`는 사용자 클릭 시 HTTP(S) 출처 링크만 엽니다. 별도의 글꼴 다운로드 패키지는 추가하지 않았으며 플랫폼의 한글 글꼴 대체를 사용합니다.
