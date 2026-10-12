"""Completed turns, owned conversation metadata and safe Phase 3 migrations."""
import json
import secrets
import sqlite3
import time
from contextlib import closing
from pathlib import Path

from langchain_core.messages import AIMessage, HumanMessage


class ConversationMissing(Exception):
    pass


class ConversationBusy(Exception):
    pass


class ConversationLimit(Exception):
    pass


class HistoryStore:
    def __init__(self, path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.path = path
        with closing(self.connect()) as db, db:
            db.execute("PRAGMA journal_mode=WAL")
            db.execute("""CREATE TABLE IF NOT EXISTS turns (
                id INTEGER PRIMARY KEY, session TEXT NOT NULL,
                question TEXT NOT NULL, answer TEXT NOT NULL, updated REAL NOT NULL)""")
            db.execute("CREATE INDEX IF NOT EXISTS turns_session ON turns(session, id)")
            # One migration lock makes simultaneous worker startup safe.
            db.execute("BEGIN IMMEDIATE")
            columns = {r["name"] for r in db.execute("PRAGMA table_info(turns)")}
            for name in ("sources", "warnings"):
                if name not in columns:
                    db.execute(f"ALTER TABLE turns ADD COLUMN {name} TEXT NOT NULL DEFAULT '[]'")
            db.execute("""CREATE TABLE IF NOT EXISTS conversations (
                id TEXT PRIMARY KEY, owner TEXT NOT NULL, title TEXT NOT NULL,
                created REAL NOT NULL, updated REAL NOT NULL, archived INTEGER NOT NULL DEFAULT 0)""")
            db.execute("CREATE INDEX IF NOT EXISTS conversations_owner ON conversations(owner, archived, updated)")
            db.execute("CREATE TABLE IF NOT EXISTS generation_leases (session TEXT PRIMARY KEY, token TEXT, expires REAL)")

    def connect(self):
        db = sqlite3.connect(self.path, timeout=5)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys=ON")
        return db

    def load(self, session: str):
        with closing(self.connect()) as db:
            rows = db.execute(
                "SELECT question, answer FROM turns WHERE session=? ORDER BY id DESC LIMIT 10",
                (session,),
            ).fetchall()
        return [message for row in reversed(rows)
                for message in (HumanMessage(content=row["question"]), AIMessage(content=row["answer"]))]

    def save(self, session: str, question: str, answer: str, sources=None, warnings=None):
        now = time.time()
        with closing(self.connect()) as db, db:
            db.execute("""INSERT INTO turns(session, question, answer, updated, sources, warnings)
                VALUES (?, ?, ?, ?, ?, ?)""", (session, question, answer, now,
                    json.dumps(sources or [], ensure_ascii=False), json.dumps(warnings or [], ensure_ascii=False)))
            db.execute("""UPDATE conversations SET updated=?,
                title=CASE WHEN title='새 대화' THEN ? ELSE title END WHERE id=?""", (now, question[:40], session))
            # UI keeps 100 completed turns; model context is independently limited to ten.
            db.execute("DELETE FROM turns WHERE session=? AND id NOT IN (SELECT id FROM turns WHERE session=? ORDER BY id DESC LIMIT 100)",
                       (session, session))

    @staticmethod
    def summary(row):
        return {"id": row["id"], "title": row["title"], "created_at": row["created"],
                "updated_at": row["updated"], "archived": bool(row["archived"])}

    def create(self, owner):
        with closing(self.connect()) as db, db:
            db.execute("BEGIN IMMEDIATE")
            if db.execute("SELECT COUNT(*) FROM conversations WHERE owner=?", (owner,)).fetchone()[0] >= 100:
                raise ConversationLimit()
            now = time.time()
            session = secrets.token_hex(24)
            db.execute("INSERT INTO conversations VALUES (?, ?, ?, ?, ?, 0)", (session, owner, "새 대화", now, now))
            return self.summary(db.execute("SELECT * FROM conversations WHERE id=?", (session,)).fetchone())

    def list_conversations(self, owner, archived=False):
        with closing(self.connect()) as db:
            rows = db.execute("SELECT * FROM conversations WHERE owner=? AND archived=? ORDER BY updated DESC LIMIT 100",
                              (owner, int(archived))).fetchall()
        return [self.summary(r) for r in rows]

    def require_active(self, session, owner):
        with closing(self.connect()) as db:
            if not db.execute("SELECT 1 FROM conversations WHERE id=? AND owner=? AND archived=0",
                              (session, owner)).fetchone():
                raise ConversationMissing()

    def detail(self, session, owner):
        with closing(self.connect()) as db:
            db.execute("BEGIN")
            row = db.execute("SELECT * FROM conversations WHERE id=? AND owner=?", (session, owner)).fetchone()
            if not row:
                raise ConversationMissing()
            turns = db.execute("SELECT question, answer, updated, sources, warnings FROM turns WHERE session=? ORDER BY id", (session,)).fetchall()
            result = self.summary(row)
            result["turns"] = [{"question": r["question"], "answer": r["answer"], "created_at": r["updated"],
                                "sources": json.loads(r["sources"]), "warnings": json.loads(r["warnings"])} for r in turns]
            return result

    def update(self, session, owner, title=None, archived=None):
        with closing(self.connect()) as db, db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT * FROM conversations WHERE id=? AND owner=?", (session, owner)).fetchone()
            if not row:
                raise ConversationMissing()
            if db.execute("SELECT 1 FROM generation_leases WHERE session=? AND expires>?", (session, time.time())).fetchone():
                raise ConversationBusy()
            db.execute("UPDATE conversations SET title=?, archived=? WHERE id=?", (
                title if title is not None else row["title"],
                int(archived) if archived is not None else row["archived"], session))
            return self.summary(db.execute("SELECT * FROM conversations WHERE id=?", (session,)).fetchone())
