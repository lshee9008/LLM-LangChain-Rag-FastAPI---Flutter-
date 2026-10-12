from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class ChatRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    session_id: str = Field(min_length=8, max_length=128, pattern=r"^[a-zA-Z0-9_-]+$")
    question: str = Field(min_length=1, max_length=2000)


class Source(BaseModel):
    id: str = ""
    kind: Literal["document", "web", "football"]
    title: str
    url: str | None = None
    excerpt: str
    retrieved_at: str
    published_at: str | None = None
    cached: bool = False


class Evidence(BaseModel):
    sources: list[Source] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


class ChatResponse(BaseModel):
    session_id: str
    answer: str
    sources: list[Source] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


class Credentials(BaseModel):
    username: str = Field(min_length=3, max_length=32, pattern=r"^[a-zA-Z0-9_]+$")
    # Do not trim or normalize passwords.
    password: str = Field(min_length=10, max_length=128, repr=False)


class ConversationTitle(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    title: str = Field(min_length=1, max_length=80)


class ArchiveRequest(BaseModel):
    archived: bool


class PinRequest(BaseModel):
    pinned: bool
