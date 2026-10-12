import sqlite3
import tempfile
import unittest
from pathlib import Path

from history import ConversationBusy, ConversationMissing, HistoryStore
from request_control import RequestControl
from config import Settings
import test_phase4 as phase4


class Phase5StoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "history.sqlite3"
        self.store = HistoryStore(self.path)

    def tearDown(self):
        self.temp.cleanup()

    def test_pin_persists_orders_first_and_does_not_change_recency(self):
        first = self.store.create("alice")["id"]
        second = self.store.create("alice")["id"]
        before = self.store.detail(first, "alice")["updated_at"]
        self.store.update(first, "alice", pinned=True)
        reopened = HistoryStore(self.path)
        self.assertEqual(reopened.list_conversations("alice")[0]["id"], first)
        self.assertEqual(reopened.detail(first, "alice")["updated_at"], before)
        self.assertEqual(len(reopened.list_conversations("alice", pinned_only=True)), 1)
        self.store.update(first, "alice", pinned=False)
        self.assertEqual(self.store.list_conversations("alice")[0]["id"], second)

    def test_search_matches_title_question_answer_and_treats_wildcards_literally(self):
        session = self.store.create("alice")["id"]
        self.store.save(session, "콜 파머 100%", "Stamford Bridge_42")
        self.store.update(session, "alice", title="런던 이야기")
        for query in ("콜 파머", "stamford", "런던", "100%", "_42"):
            self.assertEqual([r["id"] for r in self.store.list_conversations("alice", query=query)], [session])
        for query in ("없는 단어", "' OR 1=1 --", "%_"):
            self.assertFalse(self.store.list_conversations("alice", query=query))

    def test_search_pin_archive_and_owner_filters_combine(self):
        session = self.store.create("alice")["id"]
        self.store.save(session, "첼시", "비공개 답변")
        self.store.update(session, "alice", pinned=True, archived=True)
        self.assertFalse(self.store.list_conversations("bob", archived=True, query="비공개"))
        self.assertFalse(self.store.list_conversations("alice", query="비공개", pinned_only=True))
        self.assertEqual(len(self.store.list_conversations("alice", archived=True, query="비공개", pinned_only=True)), 1)
        with self.assertRaises(ConversationMissing):
            self.store.update(session, "bob", pinned=False)

    def test_phase4_migration_keeps_owned_conversation_and_pin_survives_restart(self):
        old_path = Path(self.temp.name) / "phase4.sqlite3"
        with sqlite3.connect(old_path) as db:
            db.execute("CREATE TABLE conversations (id TEXT PRIMARY KEY, owner TEXT, title TEXT, created REAL, updated REAL, archived INTEGER NOT NULL DEFAULT 0)")
            db.execute("INSERT INTO conversations VALUES ('old_chat', 'alice', '기존 대화', 1, 2, 0)")
        migrated = HistoryStore(old_path)
        self.assertEqual(migrated.detail("old_chat", "alice")["title"], "기존 대화")
        self.assertFalse(migrated.detail("old_chat", "alice")["pinned"])
        migrated.update("old_chat", "alice", pinned=True)
        self.assertTrue(HistoryStore(old_path).detail("old_chat", "alice")["pinned"])

    def test_pin_cannot_race_with_generation(self):
        session = self.store.create("alice")["id"]
        control = RequestControl(self.store, Settings(history_db=self.path))
        state, token = control.acquire(session, "alice")
        self.assertIsNone(state)
        with self.assertRaises(ConversationBusy):
            self.store.update(session, "alice", pinned=True)
        control.release(session, token)
        self.assertTrue(self.store.update(session, "alice", pinned=True)["pinned"])


class Phase5ApiTests(unittest.TestCase):
    # Reuse fixture helpers without inheriting and rerunning Phase 4 tests.
    setUp = phase4.Phase4ApiTests.setUp
    tearDown = phase4.Phase4ApiTests.tearDown
    register = phase4.Phase4ApiTests.register
    create_conversation = phase4.Phase4ApiTests.create_conversation

    def test_pin_route_search_and_validation(self):
        alice = self.register()
        session = self.create_conversation(alice)
        self.service.history.save(session, "질문", "검색할 답변")
        self.assertEqual(self.client.post(f"/api/v1/conversations/{session}/pin", json={"pinned": True}, headers=alice).status_code, 200)
        result = self.client.get("/api/v1/conversations", params={"q": "답변", "pinned_only": True}, headers=alice)
        self.assertEqual(result.json()["conversations"][0]["id"], session)
        self.assertEqual(self.client.get("/api/v1/conversations", params={"q": "a" * 81}, headers=alice).status_code, 422)
        self.assertEqual(self.client.post(f"/api/v1/conversations/{session}/pin", json={}, headers=alice).status_code, 422)

    def test_pin_route_rejects_unknown_and_other_users(self):
        alice = self.register()
        session = self.create_conversation(alice)
        bob = self.register("bob")
        for id_ in (session, "unknown_chat"):
            self.assertEqual(self.client.post(f"/api/v1/conversations/{id_}/pin", json={"pinned": True}, headers=bob).status_code, 404)
        self.client.cookies.clear()
        self.assertEqual(self.client.post(f"/api/v1/conversations/{session}/pin", json={"pinned": True}).status_code, 401)


if __name__ == "__main__":
    unittest.main()
