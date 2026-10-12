"""Persist completed turns only. Session IDs are opaque bearer identifiers."""
import sqlite3
import time
from pathlib import Path

from langchain_core.messages import AIMessage, HumanMessage


class HistoryStore:
    def __init__(self, path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.path = path
        with self.connect() as db:
            db.execute("""CREATE TABLE IF NOT EXISTS turns (
                id INTEGER PRIMARY KEY, session TEXT NOT NULL,
                question TEXT NOT NULL, answer TEXT NOT NULL, updated REAL NOT NULL)""")
            db.execute("CREATE INDEX IF NOT EXISTS turns_session ON turns(session, id)")

    def connect(self):
        return sqlite3.connect(self.path, timeout=5)

    def load(self, session: str):
        with self.connect() as db:
            rows = db.execute(
                "SELECT question, answer FROM turns WHERE session=? AND updated>? ORDER BY id DESC LIMIT 10",
                (session, time.time() - 7 * 86400),
            ).fetchall()
        return [message for q, a in reversed(rows)
                for message in (HumanMessage(content=q), AIMessage(content=a))]

    def save(self, session: str, question: str, answer: str):
        with self.connect() as db:
            db.execute("INSERT INTO turns(session, question, answer, updated) VALUES (?, ?, ?, ?)",
                       (session, question, answer, time.time()))
            db.execute("DELETE FROM turns WHERE session=? AND id NOT IN (SELECT id FROM turns WHERE session=? ORDER BY id DESC LIMIT 10)",
                       (session, session))
            db.execute("DELETE FROM turns WHERE updated<?", (time.time() - 7 * 86400,))
            db.execute("""DELETE FROM turns WHERE session NOT IN (
                SELECT session FROM turns GROUP BY session ORDER BY MAX(updated) DESC LIMIT 1000)""")
