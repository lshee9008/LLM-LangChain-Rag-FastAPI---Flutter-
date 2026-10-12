# Chelsea FC Blues Bot · Phase 3

첼시 팬을 위한 **비공식** 챗봇입니다. 구단 문서 RAG에 Tavily 웹 검색과 API-Football 통계를 결합하고, Flutter 화면으로 실제 LLM 토큰을 스트리밍합니다.

![Phase 3 화면](docs/images/phase3-welcome.jpg)

## 시작하기

Python 3.10.12 이상과 uv, Dart 3.13.2 이상을 포함한 Flutter가 필요합니다. 검증 환경은 Python 3.10, Flutter 3.47.2 / Dart 3.13.2입니다.

```sh
cd back
cp -n .env.example .env
# .env에 API 키 입력. 기존 .env는 덮어쓰지 않습니다.
uv sync --locked
uv run uvicorn main:app --host 127.0.0.1 --port 8000
```

다른 터미널에서:

```sh
cd front/front
flutter pub get
flutter run -d chrome --web-port 5173 --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

브라우저 주소와 `CORS_ORIGINS`가 일치해야 합니다. 기본값은 `http://localhost:5173,http://127.0.0.1:5173`입니다. API 상태는 `http://127.0.0.1:8000/health`, 명세는 `http://127.0.0.1:8000/docs`에서 확인합니다.

## 연동 설정

| 환경 변수 | 용도 | 미설정 시 |
| --- | --- | --- |
| `OPENAI_API_KEY` | 도구 선택, 답변 생성, 임베딩 | 채팅 API가 503으로 안내 |
| `TAVILY_API_KEY` | 최근 일주일 뉴스 / 일반 웹 검색 | 웹 검색 제한 안내 |
| `API_FOOTBALL_KEY` | 경기 결과·일정·순위·선수 통계 | 축구 API 제한 안내 |
| `OPENAI_MODEL` | 기본 `gpt-4o-mini` | 기본값 사용 |
| `OPENAI_EMBEDDING_MODEL` | 기본 `text-embedding-3-small` | 기본값 사용 |
| `CORS_ORIGINS` | 허용할 프론트엔드 주소 | 로컬 5173 포트 허용 |

API-Football은 **API-SPORTS 직접 가입 계정의 키**와 `x-apisports-key` 헤더를 사용합니다. RapidAPI 키는 이 설정과 호환되지 않습니다. 요금제별로 최신 시즌, `last`/`next`, 경기별 선수 기록의 제공 범위가 다를 수 있습니다. HTTP 200의 `errors` 응답도 실패로 처리합니다.

키는 백엔드 `.env`에만 저장합니다. Flutter에는 백엔드 주소만 전달합니다. `/health`는 키의 설정 여부를 보여주며 실제 API 인증·가용성을 검사하지 않습니다.

## 질문별 조회

| 질문 | 조회 경로 |
| --- | --- |
| 첼시 홈구장 이름과 연고지 알려줘 | Chroma 구단 문서 |
| 콜 파머 최근 경기 소식 알려줘 | Tavily 뉴스 |
| 첼시 최근 5경기 결과 알려줘 | API-Football fixtures, team=49 |
| 첼시 다음 경기 일정 알려줘 | API-Football fixtures next=5 |
| 프리미어리그 순위 알려줘 | API-Football standings, league=39 |
| 콜파머 이번 시즌 골과 도움 알려줘 | players 시즌 누적 통계 |
| 콜파머 최근 경기별 기록 알려줘 | 최근 팀 5경기 + fixtures/players |

LLM이 대화를 참고해 도구와 검색어를 고릅니다. 선수 이름은 영문명을 권장하며 `콜파머`, `콜 파머`, `파머` 별칭을 지원합니다. 경기별 기록 부재를 미출전·0골로 단정하지 않습니다.

## API / 스트리밍

기존 `POST /api/v1/chat`의 `session_id`, `question`, `answer`를 유지하고 `sources`, `warnings`를 추가했습니다. 스트리밍은 같은 본문으로 `POST /api/v1/chat/stream`을 사용합니다.

```sh
curl -N http://127.0.0.1:8000/api/v1/chat/stream \
  -H 'Content-Type: application/json' \
  -d '{"session_id":"example_session_001","question":"첼시 홈구장은 어디야?"}'
```

이벤트는 `status`(여러 번) → `sources` → `token`(여러 번) → `done`입니다. 실패 시 `error`로 종료하고 `done`을 보내지 않습니다. 10초마다 SSE 주석 heartbeat를 전송합니다. 각 `data:`는 JSON입니다.

`done`에는 최종 `answer`, `sources`, `warnings`, `session_id`가 있습니다. 출처는 `id`, `kind`, `title`, `url`, `excerpt`, `retrieved_at`, `published_at`, `cached`를 포함합니다. API-Football 출처 URL은 인증이 필요한 API 주소이며 키를 포함하지 않습니다.

| 상태 | 의미 |
| --- | --- |
| 422 | 빈 질문·2,000자 초과·잘못된 세션 ID |
| 503 | OpenAI 키 미설정 |
| 409 | 같은 세션에서 이미 답변 생성 중 |
| 429 | 한 프로세스에서 활성 요청 32개 초과 |
| 502 / 504 | 일반 응답 생성 실패 / 시간 초과 |

스트리밍 시작 후 오류는 SSE `error`로 전달합니다. 외부 조회 실패는 가능한 경우 경고와 대체 검색으로 처리합니다. 근거가 없으면 확인하지 못했다고 답합니다.

## 저장 및 실행 범위

- `back/data/*.txt`를 최초 문서 검색 시 인덱싱합니다. 문서 변경은 백엔드 재시작 후 반영됩니다.
- `back/chroma_phase3/`를 사용하며 Phase 2의 `back/chroma_db/`를 보존합니다. 문서 해시로 중복 인덱싱을 피하고 임베딩 모델별 컬렉션을 분리합니다.
- 완료한 대화는 `back/runtime/history.sqlite3`에 저장합니다. 세션별 최근 10턴을 사용하며, 저장할 때 7일 지난 기록과 최근 1,000세션 밖의 기록을 정리합니다.
- 앱 실행·새 대화마다 암호학적 난수 세션 ID를 생성합니다. 백엔드 재시작 후 같은 ID로 요청하면 문맥이 이어집니다. **앱 재실행 후 세션 복원·대화 목록 UI는 아직 없습니다.**
- 외부 결과 캐시는 프로세스 내 60초 / 최대 128항목입니다. 캐시를 사용해도 최초 조회 시각을 유지합니다.
- 도구 선택은 최대 3라운드·실제 도구 호출 6회입니다. 경기별 통계 도구 1회는 경기 조회 1회와 선수 기록 최대 5회를 수행합니다. 전체 요청은 120초 제한입니다.
- 이 버전은 **로컬 단일 프로세스 MVP**입니다. 로그인, 세션 소유권 검증, 분산 잠금, 사용자별 요금 제어는 포함하지 않습니다. 공개 배포 전 인증과 세션 소유권 검증이 필요합니다.

Android 에뮬레이터는 `--dart-define=API_BASE_URL=http://10.0.2.2:8000`을 사용합니다. 로컬 HTTP는 debug 빌드에서 허용합니다. 실제 기기는 접근 가능한 HTTPS 주소를 지정하세요. macOS는 네트워크 클라이언트 권한을 추가했습니다. 모바일·데스크톱 바이너리 빌드는 이번 검증에 포함하지 않았습니다.

## 검증

```sh
cd back
uv run python -m unittest discover -s tests -v
cd ../front/front
flutter analyze
flutter test
flutter build web --release --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

검증 결과와 개발기는 [Phase 3 블로그 초안](docs/phase3-blog.md)에 정리했습니다. 모의 테스트와 실제 공급자 호출 결과는 구분해서 기록합니다.
