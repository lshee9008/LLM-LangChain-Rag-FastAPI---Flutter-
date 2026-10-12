"""Configuration is loaded explicitly; importing the API never calls a provider."""
import os
from dataclasses import dataclass, field
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent


@dataclass(frozen=True)
class Settings:
    openai_api_key: str = field(default="", repr=False)
    tavily_api_key: str = field(default="", repr=False)
    football_api_key: str = field(default="", repr=False)
    model: str = "gpt-4o-mini"
    embedding_model: str = "text-embedding-3-small"
    data_dir: Path = BASE_DIR / "data"
    chroma_dir: Path = BASE_DIR / "chroma_phase3"
    history_db: Path = BASE_DIR / "runtime" / "history.sqlite3"
    cors_origins: tuple[str, ...] = ("http://localhost:5173", "http://127.0.0.1:5173")
    provider_timeout: float = 15.0
    request_timeout: float = 120.0
    cache_ttl: float = 60.0
    max_tool_calls: int = 6
    cookie_secure: bool = False
    registration_enabled: bool = True
    chat_requests_per_minute: int = 20
    auth_requests_per_minute: int = 10

    @classmethod
    def from_env(cls):
        load_dotenv(BASE_DIR / ".env", override=False)
        return cls(
            openai_api_key=os.getenv("OPENAI_API_KEY", ""),
            tavily_api_key=os.getenv("TAVILY_API_KEY", ""),
            football_api_key=os.getenv("API_FOOTBALL_KEY", ""),
            model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
            embedding_model=os.getenv("OPENAI_EMBEDDING_MODEL", "text-embedding-3-small"),
            cookie_secure=os.getenv("AUTH_COOKIE_SECURE", "false").lower() == "true",
            registration_enabled=os.getenv("ALLOW_REGISTRATION", "true").lower() == "true",
            cors_origins=tuple(x.strip() for x in os.getenv(
                "CORS_ORIGINS", "http://localhost:5173,http://127.0.0.1:5173"
            ).split(",") if x.strip()),
        )
