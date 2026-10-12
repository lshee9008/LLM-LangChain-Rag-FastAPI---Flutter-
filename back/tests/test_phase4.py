import asyncio
import hashlib
import sqlite3
import sys
import tempfile
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch

import httpx
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from auth import COOKIE_NAME, hash_password, verify_password
from chain_service import ChatService
from config import Settings
from history import ConversationBusy, ConversationMissing, HistoryStore
from main import create_app
from providers import LiveData
from request_control import RequestControl
from test_phase3 import FakeKnowledge, FakeModel


class Phase4ApiTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "phase4.sqlite3"
        self.settings = Settings(openai_api_key="test", history_db=self.path)
        self.http = httpx.AsyncClient()
        self.service = ChatService(self.settings, LiveData(self.settings, self.http), FakeKnowledge(), FakeModel())
        self.app = create_app(self.settings, self.service)
        self.client = TestClient(self.app).__enter__()

    def tearDown(self):
        self.client.__exit__(None, None, None)
        asyncio.run(self.http.aclose())
        self.temp.cleanup()

    def register(self, username="alice"):
        response = self.client.post("/api/v1/auth/register", json={"username": username, "password": "test-password-42"}, headers={"X-Client-Platform": "native"})
        self.assertEqual(response.status_code, 201, response.text)
        return {"Authorization": "Bearer " + response.json()["token"]}

    def create_conversation(self, headers):
        response = self.client.post("/api/v1/conversations", headers=headers)
        self.assertEqual(response.status_code, 201)
        return response.json()["id"]

    def test_cookie_login_restore_logout_and_hash_storage(self):
        response = self.client.post("/api/v1/auth/register", json={"username": "ChelseaFan", "password": "test-password-42"})
        self.assertEqual(response.status_code, 201)
        self.assertNotIn("token", response.json())
        self.assertIn("HttpOnly", response.headers["set-cookie"])
        self.assertIn("SameSite=lax", response.headers["set-cookie"])
        self.assertEqual(response.headers["cache-control"], "no-store")
        self.assertEqual(self.client.get("/api/v1/auth/me").json()["user"]["username"], "chelseafan")
        cookie = self.client.cookies.get(COOKIE_NAME)
        with self.service.history.connect() as db:
            user = db.execute("SELECT password_hash FROM users").fetchone()
            session = db.execute("SELECT token_hash FROM auth_sessions").fetchone()
        self.assertNotIn("test-password-42", user[0])
        self.assertEqual(session[0], hashlib.sha256(cookie.encode()).hexdigest())
        self.assertEqual(self.client.post("/api/v1/auth/logout").status_code, 200)
        self.assertEqual(self.client.get("/api/v1/auth/me").status_code, 401)
        self.assertEqual(self.client.get("/api/v1/auth/me", headers={"Authorization": "Bearer " + cookie}).status_code, 401)
        self.assertEqual(self.client.post("/api/v1/auth/login", json={"username": "CHELSEAFAN", "password": "test-password-42"}).status_code, 200)

    def test_unauthenticated_routes_are_closed(self):
        for method, path, data in [("get", "/api/v1/conversations", None), ("post", "/api/v1/conversations", None),
                                   ("get", "/api/v1/conversations/known_id", None),
                                   ("post", "/api/v1/chat", {"session_id": "known_id", "question": "홈구장"}),
                                   ("post", "/api/v1/chat/stream", {"session_id": "known_id", "question": "홈구장"})]:
            response = self.client.request(method, path, json=data)
            self.assertEqual(response.status_code, 401)

    def test_cross_user_access_is_denied_everywhere(self):
        alice = self.register("alice")
        session = self.create_conversation(alice)
        bob = self.register("bob")
        self.assertFalse(self.client.get("/api/v1/conversations", headers=bob).json()["conversations"])
        for method, path, data in [("GET", f"/api/v1/conversations/{session}", None),
                                   ("PATCH", f"/api/v1/conversations/{session}", {"title": "changed"}),
                                   ("POST", f"/api/v1/conversations/{session}/archive", {"archived": True}),
                                   ("POST", "/api/v1/chat", {"session_id": session, "question": "홈구장"}),
                                   ("POST", "/api/v1/chat/stream", {"session_id": session, "question": "홈구장"})]:
            self.assertEqual(self.client.request(method, path, json=data, headers=bob).status_code, 404)
        self.assertEqual(self.client.get(f"/api/v1/conversations/{session}", headers=alice).status_code, 200)

    def test_completed_turn_restores_sources_and_warnings_and_title(self):
        alice = self.register()
        session = self.create_conversation(alice)
        result = self.client.post("/api/v1/chat", json={"session_id": session, "question": "홈구장 알려줘"}, headers=alice)
        self.assertEqual(result.status_code, 200)
        detail = self.client.get(f"/api/v1/conversations/{session}", headers=alice).json()
        self.assertEqual(detail["title"], "홈구장 알려줘")
        self.assertEqual(detail["turns"][0]["sources"], result.json()["sources"])
        self.assertEqual(detail["turns"][0]["answer"], result.json()["answer"])
        reopened = HistoryStore(self.path)
        self.assertEqual(reopened.detail(session, self.client.get("/api/v1/auth/me", headers=alice).json()["user"]["id"]), detail)

    def test_rename_archive_restore_and_empty_title_validation(self):
        alice = self.register()
        session = self.create_conversation(alice)
        self.assertEqual(self.client.patch(f"/api/v1/conversations/{session}", json={"title": "  경기 분석  "}, headers=alice).json()["title"], "경기 분석")
        self.assertEqual(self.client.patch(f"/api/v1/conversations/{session}", json={"title": "  "}, headers=alice).status_code, 422)
        self.client.post(f"/api/v1/conversations/{session}/archive", json={"archived": True}, headers=alice)
        self.assertFalse(self.client.get("/api/v1/conversations", headers=alice).json()["conversations"])
        self.assertEqual(len(self.client.get("/api/v1/conversations?archived=true", headers=alice).json()["conversations"]), 1)
        self.assertEqual(self.client.post("/api/v1/chat", json={"session_id": session, "question": "홈구장"}, headers=alice).status_code, 404)
        self.client.post(f"/api/v1/conversations/{session}/archive", json={"archived": False}, headers=alice)
        self.assertEqual(len(self.client.get("/api/v1/conversations", headers=alice).json()["conversations"]), 1)

    def test_foreign_origins_rejected_and_preflight_allows_credentials(self):
        alice = self.register()
        response = self.client.post("/api/v1/conversations", headers={**alice, "Origin": "https://untrusted.example"})
        self.assertEqual(response.status_code, 403)
        response = self.client.options("/api/v1/conversations", headers={"Origin": "http://127.0.0.1:5173", "Access-Control-Request-Method": "POST"})
        self.assertEqual(response.headers["access-control-allow-credentials"], "true")
        with self.assertRaises(ValueError):
            create_app(Settings(cors_origins=("*",)))

    def test_password_input_not_echoed_and_invalid_credentials_are_generic(self):
        alice = self.register()
        response = self.client.post("/api/v1/auth/login", json={"username": "alice", "password": "sensitive"})
        self.assertEqual(response.status_code, 422)
        self.assertNotIn("sensitive", response.text)
        known = self.client.post("/api/v1/auth/login", json={"username": "alice", "password": "wrong-password-42"})
        unknown = self.client.post("/api/v1/auth/login", json={"username": "unknown", "password": "wrong-password-42"})
        self.assertEqual(known.status_code, 401)
        self.assertEqual(known.json(), unknown.json())

    def test_expired_auth_token_is_rejected(self):
        alice = self.register()
        with self.service.history.connect() as db:
            db.execute("UPDATE auth_sessions SET expires=0")
        self.assertEqual(self.client.get("/api/v1/auth/me", headers=alice).status_code, 401)

    def test_ownership_is_checked_even_when_model_is_not_configured(self):
        alice = self.register()
        session = self.create_conversation(alice)
        bob = self.register("bob")
        with TestClient(create_app(Settings(history_db=self.path), self.service)) as client:
            self.assertEqual(client.post("/api/v1/chat", json={"session_id": session, "question": "hello"}, headers=bob).status_code, 404)
            self.assertEqual(client.post("/api/v1/chat", json={"session_id": session, "question": "hello"}, headers=alice).status_code, 503)

    @patch("request_control.time.time", return_value=1_800_000_001.0)
    def test_auth_rate_limit_applies_across_endpoints(self, clock):
        body = {"username": "unknown", "password": "wrong-password-42"}
        for _ in range(self.settings.auth_requests_per_minute):
            self.assertEqual(self.client.post("/api/v1/auth/login", json=body).status_code, 401)
        response = self.client.post("/api/v1/auth/register", json=body)
        self.assertEqual(response.status_code, 429)
        self.assertEqual(response.headers["retry-after"], "60")

    def test_secure_cookie_and_registration_switch(self):
        secure_app = create_app(Settings(history_db=self.path, cookie_secure=True), self.service)
        with TestClient(secure_app, base_url="https://testserver") as client:
            response = client.post("/api/v1/auth/register", json={"username": "secure_user", "password": "test-password-42"})
            self.assertIn("Secure", response.headers["set-cookie"])
            self.assertEqual(client.get("/api/v1/auth/me").status_code, 200)
        with TestClient(create_app(Settings(history_db=self.path, registration_enabled=False), self.service)) as client:
            self.assertEqual(client.post("/api/v1/auth/register", json={"username": "disabled_user", "password": "test-password-42"}).status_code, 403)


class StorageAndLeaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "storage.sqlite3"
        self.history = HistoryStore(self.path)
        self.settings = Settings(history_db=self.path, chat_requests_per_minute=2)
        self.control = RequestControl(self.history, self.settings)

    def tearDown(self):
        self.temp.cleanup()

    def test_atomic_lease_acquisition_across_workers(self):
        session = self.history.create("owner")["id"]
        other = RequestControl(HistoryStore(self.path), self.settings)
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda control: control.acquire(session, "owner"), [self.control, other]))
        self.assertEqual(sum(state is None for state, token in results), 1)
        self.assertEqual(sum(state == "busy" for state, token in results), 1)

    def test_expired_leases_can_recover_and_old_release_cannot_remove_new_lease(self):
        session = self.history.create("owner")["id"]
        _, old = self.control.acquire(session, "owner")
        with self.history.connect() as db:
            db.execute("UPDATE generation_leases SET expires=0")
        state, new = self.control.acquire(session, "owner")
        self.assertIsNone(state)
        self.control.release(session, old)
        self.assertEqual(self.control.acquire(session, "owner")[0], "busy")
        self.control.release(session, new)

    @patch("request_control.time.time", return_value=1_800_000_001.0)
    def test_per_user_budget_is_shared_across_conversations(self, clock):
        for _ in range(2):
            session = self.history.create("owner")["id"]
            state, token = self.control.acquire(session, "owner")
            self.assertIsNone(state)
            self.control.release(session, token)
        session = self.history.create("owner")["id"]
        self.assertEqual(RequestControl(HistoryStore(self.path), self.settings).acquire(session, "owner")[0], "rate")
        other = self.history.create("other")["id"]
        self.assertIsNone(self.control.acquire(other, "other")[0])

    def test_global_capacity_is_shared_across_workers(self):
        settings = Settings(history_db=self.path, chat_requests_per_minute=100)
        control = RequestControl(self.history, settings)
        for _ in range(32):
            session = self.history.create("owner")["id"]
            self.assertIsNone(control.acquire(session, "owner")[0])
        other = RequestControl(HistoryStore(self.path), settings)
        session = self.history.create("owner")["id"]
        self.assertEqual(other.acquire(session, "owner")[0], "capacity")

    def test_busy_conversation_cannot_be_archived_or_renamed(self):
        session = self.history.create("owner")["id"]
        _, token = self.control.acquire(session, "owner")
        with self.assertRaises(ConversationBusy):
            self.history.update(session, "owner", archived=True)
        self.control.release(session, token)
        self.assertTrue(self.history.update(session, "owner", archived=True)["archived"])

    def test_phase3_migration_preserves_unowned_turns_without_exposing_them(self):
        path = Path(self.temp.name) / "legacy.sqlite3"
        with sqlite3.connect(path) as db:
            db.execute("CREATE TABLE turns(id INTEGER PRIMARY KEY, session TEXT, question TEXT, answer TEXT, updated REAL)")
            db.execute("INSERT INTO turns VALUES (1, 'legacy_session', 'private question', 'private answer', ?)", (time.time(),))
        migrated = HistoryStore(path)
        self.assertEqual(migrated.load("legacy_session")[0].content, "private question")
        self.assertFalse(migrated.list_conversations("new_user"))
        with self.assertRaises(ConversationMissing):
            migrated.detail("legacy_session", "new_user")

    def test_display_keeps_more_than_model_context_and_saves_warnings(self):
        session = self.history.create("owner")["id"]
        for i in range(112):
            self.history.save(session, f"question {i}", f"answer {i}", warnings=["제공처 확인 필요"])
        self.assertEqual(len(self.history.load(session)), 20)
        detail = self.history.detail(session, "owner")
        self.assertEqual(len(detail["turns"]), 100)
        self.assertEqual(detail["turns"][0]["question"], "question 12")
        self.assertEqual(detail["turns"][-1]["warnings"], ["제공처 확인 필요"])

    def test_passwords_are_salted_and_not_trimmed(self):
        first = hash_password(" password-with-spaces ")
        second = hash_password(" password-with-spaces ")
        self.assertNotEqual(first, second)
        self.assertTrue(verify_password(" password-with-spaces ", first))
        self.assertFalse(verify_password("password-with-spaces", first))


if __name__ == "__main__":
    unittest.main()
