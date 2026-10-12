"""Password hashing and revocable, hashed opaque sessions; no signing secret needed."""
import hashlib
import hmac
import secrets
import sqlite3
import time
from contextlib import closing

COOKIE_NAME = "blues_session"
SESSION_SECONDS = 7 * 86400
PASSWORD_ITERATIONS = 600_000


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, PASSWORD_ITERATIONS)
    return f"pbkdf2_sha256${PASSWORD_ITERATIONS}${salt.hex()}${digest.hex()}"


def verify_password(password: str, encoded: str) -> bool:
    try:
        algorithm, iterations, salt, expected = encoded.split("$")
        if algorithm != "pbkdf2_sha256":
            return False
        digest = hashlib.pbkdf2_hmac("sha256", password.encode(), bytes.fromhex(salt), int(iterations))
        return hmac.compare_digest(digest.hex(), expected)
    except (ValueError, TypeError):
        return False


class AuthStore:
    def __init__(self, history):
        self.history = history
        with closing(history.connect()) as db, db:
            db.execute("""CREATE TABLE IF NOT EXISTS users (
                id TEXT PRIMARY KEY, username TEXT UNIQUE NOT NULL,
                password_hash TEXT NOT NULL, created REAL NOT NULL)""")
            db.execute("""CREATE TABLE IF NOT EXISTS auth_sessions (
                token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL,
                expires REAL NOT NULL, FOREIGN KEY(user_id) REFERENCES users(id))""")
        # Unknown usernames still perform the same password KDF as known users.
        self.dummy_hash = hash_password(secrets.token_urlsafe(24))

    def register(self, username, password):
        user = {"id": secrets.token_hex(16), "username": username.lower()}
        encoded = hash_password(password)
        try:
            with closing(self.history.connect()) as db, db:
                db.execute("INSERT INTO users VALUES (?, ?, ?, ?)",
                           (user["id"], user["username"], encoded, time.time()))
        except sqlite3.IntegrityError:
            return None
        return user

    def login(self, username, password):
        with closing(self.history.connect()) as db:
            row = db.execute("SELECT id, username, password_hash FROM users WHERE username=?",
                             (username.lower(),)).fetchone()
        valid = verify_password(password, row["password_hash"] if row else self.dummy_hash)
        return {"id": row["id"], "username": row["username"]} if row and valid else None

    def issue(self, user_id):
        token = secrets.token_urlsafe(32)
        with closing(self.history.connect()) as db, db:
            db.execute("DELETE FROM auth_sessions WHERE expires<=?", (time.time(),))
            db.execute("INSERT INTO auth_sessions VALUES (?, ?, ?)",
                       (hashlib.sha256(token.encode()).hexdigest(), user_id, time.time() + SESSION_SECONDS))
            # Bound remembered logins per user; oldest sessions expire first.
            db.execute("""DELETE FROM auth_sessions WHERE user_id=? AND token_hash NOT IN (
                SELECT token_hash FROM auth_sessions WHERE user_id=? ORDER BY expires DESC LIMIT 10)""",
                       (user_id, user_id))
        return token

    def authenticate(self, token):
        if not token or len(token) > 256:
            return None
        with closing(self.history.connect()) as db:
            row = db.execute("""SELECT u.id, u.username FROM auth_sessions s
                JOIN users u ON u.id=s.user_id WHERE s.token_hash=? AND s.expires>?""",
                             (hashlib.sha256(token.encode()).hexdigest(), time.time())).fetchone()
        return dict(row) if row else None

    def revoke(self, token):
        with closing(self.history.connect()) as db, db:
            db.execute("DELETE FROM auth_sessions WHERE token_hash=?", (hashlib.sha256(token.encode()).hexdigest(),))
