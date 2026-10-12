"""SQLite transactions coordinate limits and generation leases across local workers."""
import secrets
import time
from contextlib import closing


class RequestControl:
    def __init__(self, history, settings):
        self.history, self.settings = history, settings
        with closing(history.connect()) as db, db:
            db.execute("CREATE TABLE IF NOT EXISTS request_buckets (key TEXT PRIMARY KEY, window INTEGER, count INTEGER)")
            db.execute("CREATE TABLE IF NOT EXISTS generation_leases (session TEXT PRIMARY KEY, token TEXT, expires REAL)")

    def consume(self, key, limit):
        with closing(self.history.connect()) as db, db:
            db.execute("BEGIN IMMEDIATE")
            return self._consume(db, key, limit)

    @staticmethod
    def _consume(db, key, limit):
        window = int(time.time() // 60)
        db.execute("DELETE FROM request_buckets WHERE window<?", (window - 1,))
        row = db.execute("SELECT window, count FROM request_buckets WHERE key=?", (key,)).fetchone()
        count = row["count"] if row and row["window"] == window else 0
        if count >= limit:
            return False
        db.execute("INSERT OR REPLACE INTO request_buckets VALUES (?, ?, ?)", (key, window, count + 1))
        return True

    def acquire(self, session, owner):
        with closing(self.history.connect()) as db, db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT owner, archived FROM conversations WHERE id=?", (session,)).fetchone()
            if not row or row["owner"] != owner or row["archived"]:
                return "missing", None
            db.execute("DELETE FROM generation_leases WHERE expires<=?", (time.time(),))
            if db.execute("SELECT 1 FROM generation_leases WHERE session=?", (session,)).fetchone():
                return "busy", None
            if db.execute("SELECT COUNT(*) FROM generation_leases").fetchone()[0] >= 32:
                return "capacity", None
            if not self._consume(db, "chat:" + owner, self.settings.chat_requests_per_minute):
                return "rate", None
            token = secrets.token_hex(16)
            db.execute("INSERT INTO generation_leases VALUES (?, ?, ?)",
                       (session, token, time.time() + self.settings.request_timeout + 30))
            return None, token

    def release(self, session, token):
        with closing(self.history.connect()) as db, db:
            db.execute("DELETE FROM generation_leases WHERE session=? AND token=?", (session, token))
