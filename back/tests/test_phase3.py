import asyncio
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import httpx
from fastapi.testclient import TestClient
from langchain_core.messages import AIMessage, AIMessageChunk

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from chain_service import ChatService
from config import Settings
from history import HistoryStore
from main import create_app, encode_event
from providers import LiveData, safe_url
from rag_service import ChelseaKnowledge
from request_control import RequestControl
from schemas import ChatRequest, Evidence, Source


def document():
    return Source(kind="document", title="club.txt", excerpt="홈구장은 스탬포드 브릿지다.",
                  retrieved_at="2026-10-12T00:00:00+00:00")


class FakeKnowledge:
    async def search(self, query):
        return Evidence(sources=[document()])


class FakeModel:
    def __init__(self, decisions=None, fail=False):
        self.decisions = list(decisions or [AIMessage(content="")])
        self.fail = fail
        self.messages = None
        self.invocations = 0

    def bind_tools(self, tools):
        return self

    async def ainvoke(self, messages):
        self.invocations += 1
        return self.decisions.pop(0) if self.decisions else AIMessage(content="")

    async def astream(self, messages):
        self.messages = messages
        yield AIMessageChunk(content="스탬포드 ")
        if self.fail:
            raise RuntimeError("secret provider detail")
        yield AIMessageChunk(content="브릿지입니다. [1]")


class ProviderTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.requests = []

    def client(self, payload, status=200):
        def respond(request):
            self.requests.append(request)
            return httpx.Response(status, json=payload)
        return httpx.AsyncClient(transport=httpx.MockTransport(respond))

    async def test_web_contract_cache_and_timestamp(self):
        async with self.client({"results": [{"title": "Chelsea news", "url": "https://www.chelseafc.com/en/news/example",
                                              "content": "테스트 기사", "published_date": "2026-10-11"}]}) as client:
            provider = LiveData(Settings(tavily_api_key="test"), client)
            first = await provider.web_search("Chelsea news")
            second = await provider.web_search("Chelsea news")
        self.assertEqual(len(self.requests), 1)
        self.assertEqual(json.loads(self.requests[0].content)["time_range"], "week")
        self.assertEqual(self.requests[0].headers["authorization"], "Bearer test")
        self.assertFalse(first.sources[0].cached)
        self.assertTrue(second.sources[0].cached)
        self.assertEqual(first.sources[0].retrieved_at, second.sources[0].retrieved_at)

    async def test_http_200_provider_errors_are_not_empty_success(self):
        async with self.client({"errors": {"requests": "quota secret"}, "response": []}) as client:
            result = await LiveData(Settings(football_api_key="test"), client).football("standings")
        self.assertFalse(result.sources)
        self.assertTrue(result.warnings)
        self.assertNotIn("secret", str(result))

    async def test_non_200_and_empty_results(self):
        for code, data in [(429, {}), (200, {"results": []})]:
            async with self.client(data, code) as client:
                result = await LiveData(Settings(tavily_api_key="test"), client).web_search("news")
                self.assertFalse(result.sources)
                self.assertTrue(result.warnings)

    async def test_missing_keys_make_no_network_calls(self):
        async with self.client({}) as client:
            provider = LiveData(Settings(), client)
            self.assertTrue((await provider.web_search("news")).warnings)
            self.assertTrue((await provider.football("results")).warnings)
        self.assertFalse(self.requests)

    async def test_player_alias_and_exact_identity(self):
        rows = [{"player": {"name": "C. Palmer", "firstname": "Cole", "lastname": "Palmer"},
                 "statistics": [{"games": {"appearences": 3}}]},
                {"player": {"name": "Other Palmer", "firstname": "Other", "lastname": "Palmer"}, "statistics": []}]
        async with self.client({"errors": [], "response": rows}) as client:
            result = await LiveData(Settings(football_api_key="test"), client).football("player", "콜파머", 2026)
        self.assertIn("C. Palmer", result.sources[0].excerpt)
        self.assertNotIn("Other Palmer", result.sources[0].excerpt)
        self.assertEqual(self.requests[0].url.params["season"], "2026")
        self.assertEqual(self.requests[0].headers["x-apisports-key"], "test")

    async def test_player_recent_is_match_stats_not_season_aggregate(self):
        def respond(request):
            self.requests.append(request)
            if request.url.path == "/fixtures":
                rows = [{"fixture": {"id": 123, "date": "2026-10-01"}, "teams": {"home": {"name": "Chelsea"}}, "goals": {"home": 2, "away": 0}}]
            else:
                rows = [{"players": [{"player": {"id": 1, "name": "C. Palmer"}, "statistics": [{"goals": {"total": 1}}]}]}]
            return httpx.Response(200, json={"response": rows, "errors": []})
        async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
            result = await LiveData(Settings(football_api_key="test"), client).football("player_recent", "콜 파머")
        self.assertEqual(self.requests[1].url.path, "/fixtures/players")
        self.assertIn('"fixture_id": 123', result.sources[0].excerpt)

    def test_invalid_source_urls(self):
        for url in ["javascript:alert(1)", "file:///tmp/key", "https://user:pass@example.com", "https://["]:
            self.assertIsNone(safe_url(url))


class ServiceTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.settings = Settings(openai_api_key="test", history_db=Path(self.temp.name) / "history.sqlite3")
        self.client = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(200, json={})))

    async def asyncTearDown(self):
        await self.client.aclose()
        self.temp.cleanup()

    def service(self, model=None):
        return ChatService(self.settings, LiveData(self.settings, self.client), FakeKnowledge(), model or FakeModel())

    async def test_fallback_evidence_reaches_final_model_and_history(self):
        model = FakeModel()
        service = self.service(model)
        events = [event async for event in service.stream(ChatRequest(session_id="session_001", question="홈구장 알려줘"))]
        self.assertEqual(events[-1][0], "done")
        self.assertEqual(sum(e == "token" for e, _ in events), 2)
        self.assertIn("홈구장은 스탬포드", str(model.messages))
        self.assertEqual(len(service.history.load("session_001")), 2)
        self.assertEqual(HistoryStore(self.settings.history_db).load("session_001")[-1].content, events[-1][1]["answer"])
        self.assertFalse(service.history.load("session_002"))

    async def test_live_question_without_keys_does_not_use_model_memory(self):
        model = FakeModel()
        events = [e async for e in self.service(model).stream(ChatRequest(session_id="session_001", question="콜파머 최근 경기 알려줘"))]
        self.assertEqual(model.invocations, 0)
        self.assertFalse(events[-1][1]["sources"])
        self.assertIn("최신 정보", events[-1][1]["answer"])
        self.assertTrue(events[-1][1]["warnings"])

    async def test_tool_loop_validates_arguments_and_is_bounded(self):
        calls = [{"name": "search_club_documents", "args": {"query": "Chelsea"}, "id": str(i), "type": "tool_call"} for i in range(8)]
        model = FakeModel([AIMessage(content="", tool_calls=calls)])
        events = [e async for e in self.service(model).stream(ChatRequest(session_id="session_001", question="홈구장"))]
        self.assertEqual(events[-1][0], "done")
        self.assertEqual(len(events[-1][1]["sources"]), 1)
        self.assertIn("호출 한도", str(model.messages))

    async def test_latest_question_cannot_be_answered_from_static_documents_only(self):
        settings = Settings(openai_api_key="test", tavily_api_key="test", history_db=self.settings.history_db)
        decision = AIMessage(content="", tool_calls=[{"name": "search_club_documents", "args": {"query": "최신 감독"}, "id": "1", "type": "tool_call"}])
        model = FakeModel([decision])
        service = ChatService(settings, LiveData(settings, self.client), FakeKnowledge(), model)
        events = [e async for e in service.stream(ChatRequest(session_id="session_001", question="현재 감독 알려줘"))]
        self.assertIn("근거를 확보하지 못했습니다", events[-1][1]["answer"])
        self.assertIsNone(model.messages)  # Final generation was never invoked.

    def test_history_is_bounded_and_survives_reopening(self):
        history = HistoryStore(self.settings.history_db)
        for i in range(15):
            history.save("session_001", f"question {i}", f"answer {i}")
        messages = HistoryStore(self.settings.history_db).load("session_001")
        self.assertEqual(len(messages), 20)
        self.assertEqual(messages[0].content, "question 5")
        self.assertEqual(messages[-1].content, "answer 14")

    async def test_failed_or_cancelled_reply_is_not_saved(self):
        for fail in [True, False]:
            service = self.service(FakeModel(fail=fail))
            stream = service.stream(ChatRequest(session_id="session_001", question="홈구장"))
            if fail:
                with self.assertRaises(RuntimeError):
                    async for _ in stream:
                        pass
            else:
                async for event, data in stream:
                    if event == "token":
                        await stream.aclose()
                        break
            self.assertFalse(service.history.load("session_001"))

    def test_same_session_reservation(self):
        service = self.service()
        control = RequestControl(service.history, self.settings)
        session = service.history.create("owner")["id"]
        state, token = control.acquire(session, "owner")
        self.assertIsNone(state)
        self.assertEqual(control.acquire(session, "owner")[0], "busy")
        control.release(session, token)
        self.assertIsNone(control.acquire(session, "owner")[0])


class IndexTests(unittest.TestCase):
    def test_index_is_idempotent_and_replaces_changed_documents(self):
        class Store:
            def __init__(self):
                self.ids = set()
                self.adds = 0
            def get(self):
                return {"ids": list(self.ids)}
            def add_documents(self, docs, ids):
                self.ids.update(ids)
                self.adds += 1
            def delete(self, ids):
                self.ids.difference_update(ids)
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            source = directory / "club.txt"
            source.write_text("Chelsea club document", encoding="utf-8")
            store = Store()
            with patch("rag_service.Chroma", return_value=store), patch("rag_service.OpenAIEmbeddings"):
                knowledge = ChelseaKnowledge(Settings(data_dir=directory, chroma_dir=directory / "chroma", openai_api_key="test"))
                knowledge._initialize()
                original = set(store.ids)
                knowledge._initialize()
                self.assertEqual(store.adds, 1)
                source.write_text("Changed club document", encoding="utf-8")
                knowledge._initialize()
                self.assertEqual(store.adds, 2)
                self.assertFalse(original & store.ids)
                self.assertEqual(len(store.ids), 1)
class ApiTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.settings = Settings(openai_api_key="test", history_db=Path(self.temp.name) / "api.sqlite3")
        self.http = httpx.AsyncClient()

    def tearDown(self):
        asyncio.run(self.http.aclose())
        self.temp.cleanup()

    def service(self, model=None):
        return ChatService(self.settings, LiveData(self.settings, self.http), FakeKnowledge(), model or FakeModel())

    def authorize(self, client):
        response = client.post("/api/v1/auth/register", json={"username": "phase3_user", "password": "test-password-42"})
        self.assertEqual(response.status_code, 201)
        return client.post("/api/v1/conversations").json()["id"]

    def test_rest_sse_validation_and_cors(self):
        service = self.service()
        with TestClient(create_app(self.settings, service)) as client:
            self.assertTrue(client.get("/health").json()["capabilities"]["chat"])
            session = self.authorize(client)
            body = {"session_id": session, "question": "홈구장"}
            self.assertEqual(client.post("/api/v1/chat", json=body).status_code, 200)
            response = client.post("/api/v1/chat/stream", json=body)
            self.assertIn("text/event-stream", response.headers["content-type"])
            self.assertIn("event: done", response.text)
            self.assertIn("event: token", response.text)
            self.assertFalse(service.history.connect().execute("SELECT * FROM generation_leases").fetchall())
            for question in [" ", "x" * 2001]:
                self.assertEqual(client.post("/api/v1/chat", json={**body, "question": question}).status_code, 422)
            preflight = client.options("/api/v1/chat/stream", headers={"origin": "http://localhost:5173", "access-control-request-method": "POST"})
            self.assertEqual(preflight.headers["access-control-allow-origin"], "http://localhost:5173")
            self.assertEqual(client.options("/api/v1/chat/stream", headers={"origin": "https://untrusted.example", "access-control-request-method": "POST"}).status_code, 400)

    def test_stream_error_is_safe_and_does_not_emit_done(self):
        service = self.service(FakeModel(fail=True))
        with TestClient(create_app(self.settings, service)) as client:
            session = self.authorize(client)
            response = client.post("/api/v1/chat/stream", json={"session_id": session, "question": "홈구장"})
        self.assertIn("event: error", response.text)
        self.assertNotIn("event: done", response.text)
        self.assertNotIn("secret", response.text)
        self.assertFalse(service.history.connect().execute("SELECT * FROM generation_leases").fetchall())

    def test_stream_timeout_releases_session_and_does_not_store_partial_turn(self):
        class SlowModel(FakeModel):
            async def ainvoke(self, messages):
                await asyncio.sleep(1)
                return AIMessage(content="")
        settings = Settings(openai_api_key="test", history_db=self.settings.history_db, request_timeout=0.02)
        service = self.service(SlowModel())
        with TestClient(create_app(settings, service)) as client:
            session = self.authorize(client)
            response = client.post("/api/v1/chat/stream", json={"session_id": session, "question": "홈구장"})
        self.assertIn("event: error", response.text)
        self.assertNotIn("event: done", response.text)
        self.assertFalse(service.history.connect().execute("SELECT * FROM generation_leases").fetchall())
        self.assertFalse(service.history.load(session))

    def test_unconfigured_and_conflicting_sessions(self):
        with TestClient(create_app(Settings(history_db=self.settings.history_db))) as client:
            session = self.authorize(client)
            self.assertEqual(client.post("/api/v1/chat", json={"session_id": session, "question": "hi"}).status_code, 503)
        service = self.service()
        with TestClient(create_app(self.settings, service)) as client:
            response = client.post("/api/v1/auth/login", json={"username": "phase3_user", "password": "test-password-42"})
            self.assertEqual(response.status_code, 200)
            session = client.post("/api/v1/conversations").json()["id"]
            user = client.get("/api/v1/auth/me").json()["user"]
            state, lease = client.app.state.control.acquire(session, user["id"])
            self.assertIsNone(state)
            self.assertEqual(client.post("/api/v1/chat/stream", json={"session_id": session, "question": "hi"}).status_code, 409)
            client.app.state.control.release(session, lease)

    def test_event_encoding_keeps_newlines_inside_json(self):
        event = encode_event("token", {"text": "안녕\n첼시"})
        self.assertEqual(event.count("\n"), 3)
        self.assertEqual(json.loads(event.split("data: ")[1]), {"text": "안녕\n첼시"})


if __name__ == "__main__":
    unittest.main()
