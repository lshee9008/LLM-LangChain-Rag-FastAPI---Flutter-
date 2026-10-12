import asyncio
import json
import logging
from contextlib import asynccontextmanager, suppress

import httpx
import anyio
from fastapi import Depends, FastAPI, HTTPException, Query, Request, Response
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, StreamingResponse

from auth import AuthStore, COOKIE_NAME, SESSION_SECONDS
from chain_service import ChatService
from history import ConversationBusy, ConversationLimit, ConversationMissing
from request_control import RequestControl
from config import Settings
from providers import LiveData
from schemas import ArchiveRequest, ChatRequest, ChatResponse, ConversationTitle, Credentials, PinRequest

logger = logging.getLogger(__name__)


def encode_event(event: str, data: dict) -> str:
    return f"event: {event}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"


def create_app(settings: Settings | None = None, service=None) -> FastAPI:
    settings = settings or Settings.from_env()

    @asynccontextmanager
    async def lifespan(app):
        async with httpx.AsyncClient(timeout=settings.provider_timeout) as client:
            app.state.chat = service or ChatService(settings, LiveData(settings, client))
            app.state.auth = await asyncio.to_thread(AuthStore, app.state.chat.history)
            app.state.control = RequestControl(app.state.chat.history, settings)
            yield

    app = FastAPI(title="Chelsea FC Blues Bot API", version="0.5.0", lifespan=lifespan)
    app.add_middleware(CORSMiddleware, allow_origins=list(settings.cors_origins),
                       allow_credentials=True, allow_methods=["GET", "POST", "PATCH"],
                       allow_headers=["Content-Type", "Accept", "Authorization", "X-Client-Platform"])

    if "*" in settings.cors_origins:
        raise ValueError("Credentialed CORS requires explicit origins")

    @app.exception_handler(RequestValidationError)
    async def invalid_input(request, error):
        # Never echo passwords or tokens in validation responses.
        errors = [{k: e[k] for k in ("loc", "msg", "type")} for e in error.errors()]
        return JSONResponse({"detail": errors}, status_code=422)

    @app.middleware("http")
    async def private_responses(request: Request, call_next):
        response = await call_next(request)
        if request.url.path.startswith("/api/"):
            response.headers["Cache-Control"] = "no-store"
        return response

    def check_origin(request: Request):
        origin = request.headers.get("origin")
        if request.method in {"POST", "PATCH", "DELETE"} and origin and origin not in settings.cors_origins:
            raise HTTPException(403, "허용되지 않은 요청입니다.")

    def request_token(request: Request):
        authorization = request.headers.get("authorization")
        if authorization:
            scheme, _, token = authorization.partition(" ")
            return token if scheme.lower() == "bearer" else ""
        return request.cookies.get(COOKIE_NAME, "")

    async def current_user(request: Request):
        check_origin(request)
        user = await asyncio.to_thread(app.state.auth.authenticate, request_token(request))
        if not user:
            raise HTTPException(401, "로그인이 필요합니다.", headers={"WWW-Authenticate": "Bearer"})
        return user

    async def auth_rate(request: Request):
        check_origin(request)
        peer = request.client.host if request.client else "unknown"
        allowed = await asyncio.to_thread(app.state.control.consume, "auth:" + peer, settings.auth_requests_per_minute)
        if not allowed:
            raise HTTPException(429, "로그인 요청이 많습니다. 잠시 후 다시 시도해 주세요.", headers={"Retry-After": "60"})

    async def auth_response(user, request, response):
        token = await asyncio.to_thread(app.state.auth.issue, user["id"])
        response.set_cookie(COOKIE_NAME, token, max_age=SESSION_SECONDS, httponly=True,
                            secure=settings.cookie_secure, samesite="lax", path="/api")
        result = {"user": user}
        # Browser clients rely exclusively on HttpOnly cookies. Native apps retain
        # this token in memory, never in plaintext persistent preferences.
        if request.headers.get("x-client-platform") == "native":
            result["token"] = token
        return result

    @app.post("/api/v1/auth/register", status_code=201)
    async def register(credentials: Credentials, request: Request, response: Response):
        await auth_rate(request)
        if not settings.registration_enabled:
            raise HTTPException(403, "현재 회원가입을 받지 않습니다.")
        user = await asyncio.to_thread(app.state.auth.register, credentials.username, credentials.password)
        if not user:
            raise HTTPException(409, "이미 사용 중인 아이디입니다.")
        return await auth_response(user, request, response)

    @app.post("/api/v1/auth/login")
    async def login(credentials: Credentials, request: Request, response: Response):
        await auth_rate(request)
        user = await asyncio.to_thread(app.state.auth.login, credentials.username, credentials.password)
        if not user:
            raise HTTPException(401, "아이디 또는 비밀번호를 확인해 주세요.")
        return await auth_response(user, request, response)

    @app.get("/api/v1/auth/me")
    async def me(user=Depends(current_user)):
        return {"user": user}

    @app.post("/api/v1/auth/logout")
    async def logout(request: Request, response: Response, user=Depends(current_user)):
        await asyncio.to_thread(app.state.auth.revoke, request_token(request))
        response.delete_cookie(COOKIE_NAME, path="/api", secure=settings.cookie_secure,
                               httponly=True, samesite="lax")
        return {"ok": True}

    @app.exception_handler(ConversationMissing)
    async def missing_conversation(request, error):
        return JSONResponse({"detail": "대화를 찾을 수 없습니다."}, status_code=404)

    @app.exception_handler(ConversationBusy)
    async def busy_conversation(request, error):
        return JSONResponse({"detail": "답변 생성이 끝난 후 대화를 변경해 주세요."}, status_code=409)

    @app.exception_handler(ConversationLimit)
    async def conversation_limit(request, error):
        return JSONResponse({"detail": "계정당 대화는 최대 100개까지 보관할 수 있습니다."}, status_code=409)

    @app.post("/api/v1/conversations", status_code=201)
    async def create_conversation(user=Depends(current_user)):
        return await asyncio.to_thread(app.state.chat.history.create, user["id"])

    @app.get("/api/v1/conversations")
    async def conversations(archived: bool = False, q: str = Query(default="", max_length=80),
                            pinned_only: bool = False, user=Depends(current_user)):
        return {"conversations": await asyncio.to_thread(app.state.chat.history.list_conversations,
                                                          user["id"], archived, q.strip(), pinned_only)}

    @app.get("/api/v1/conversations/{session_id}")
    async def conversation(session_id: str, user=Depends(current_user)):
        return await asyncio.to_thread(app.state.chat.history.detail, session_id, user["id"])

    @app.patch("/api/v1/conversations/{session_id}")
    async def rename(session_id: str, body: ConversationTitle, user=Depends(current_user)):
        return await asyncio.to_thread(app.state.chat.history.update, session_id, user["id"], title=body.title)

    @app.post("/api/v1/conversations/{session_id}/archive")
    async def archive(session_id: str, body: ArchiveRequest, user=Depends(current_user)):
        return await asyncio.to_thread(app.state.chat.history.update, session_id, user["id"], archived=body.archived)

    @app.post("/api/v1/conversations/{session_id}/pin")
    async def pin(session_id: str, body: PinRequest, user=Depends(current_user)):
        return await asyncio.to_thread(app.state.chat.history.update, session_id, user["id"], pinned=body.pinned)

    @app.get("/health")
    async def health():
        return {"status": "ok", "version": "0.5.0", "capabilities": {
            "chat": bool(settings.openai_api_key), "web_search": bool(settings.tavily_api_key),
            "football": bool(settings.football_api_key)}, "note": "설정 여부이며 외부 API 연결 상태를 보장하지 않습니다."}

    async def reserve(request, user):
        await asyncio.to_thread(app.state.chat.history.require_active, request.session_id, user["id"])
        if not settings.openai_api_key:
            raise HTTPException(503, "답변 서비스가 아직 설정되지 않았습니다.")
        state, token = await asyncio.to_thread(app.state.control.acquire, request.session_id, user["id"])
        if state:
            if state == "missing":
                raise HTTPException(404, "대화를 찾을 수 없습니다.")
            raise HTTPException(409 if state == "busy" else 429,
                                "이미 답변 중인 대화입니다." if state == "busy" else "요청이 많습니다. 잠시 후 다시 시도해 주세요.",
                                headers={"Retry-After": "60"} if state != "busy" else None)
        return app.state.chat, token

    @app.post("/api/v1/chat", response_model=ChatResponse)
    async def chat_endpoint(request: ChatRequest, user=Depends(current_user)):
        chat, lease = await reserve(request, user)

        async def complete():
            async for event, data in chat.stream(request):
                if event == "done":
                    return ChatResponse(**data)
            raise RuntimeError("incomplete response")

        try:
            return await asyncio.wait_for(complete(), timeout=settings.request_timeout)
        except asyncio.TimeoutError:
            raise HTTPException(504, "답변 시간이 초과되었습니다. 다시 시도해 주세요.") from None
        except Exception as error:
            logger.warning("chat_failed type=%s", type(error).__name__)
            raise HTTPException(502, "답변 생성에 실패했습니다. 잠시 후 다시 시도해 주세요.") from None
        finally:
            with anyio.CancelScope(shield=True):
                await asyncio.to_thread(app.state.control.release, request.session_id, lease)

    @app.post("/api/v1/chat/stream")
    async def stream_endpoint(request: ChatRequest, user=Depends(current_user)):
        chat, lease = await reserve(request, user)

        async def events():
            queue = asyncio.Queue(maxsize=32)

            async def produce():
                cancelled = False
                async def pump():
                    async for event, data in chat.stream(request):
                        await queue.put(encode_event(event, data))
                try:
                    await asyncio.wait_for(pump(), timeout=settings.request_timeout)
                except asyncio.CancelledError:
                    cancelled = True
                    raise
                except asyncio.TimeoutError:
                    await queue.put(encode_event("error", {"message": "답변 시간이 초과되었습니다. 다시 시도해 주세요."}))
                except Exception as error:
                    logger.warning("stream_failed type=%s", type(error).__name__)
                    await queue.put(encode_event("error", {"message": "답변 생성에 실패했습니다. 잠시 후 다시 시도해 주세요."}))
                finally:
                    # A cancelled producer must not block on a full, abandoned queue.
                    if not cancelled:
                        await queue.put(None)

            producer = asyncio.create_task(produce())
            try:
                while True:
                    try:
                        item = await asyncio.wait_for(queue.get(), timeout=10)
                    except asyncio.TimeoutError:
                        yield ": keep-alive\n\n"
                        continue
                    if item is None:
                        break
                    yield item
            finally:
                producer.cancel()
                with suppress(asyncio.CancelledError):
                    await producer
                with anyio.CancelScope(shield=True):
                    await asyncio.to_thread(app.state.control.release, request.session_id, lease)

        return StreamingResponse(events(), media_type="text/event-stream",
                                 headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})

    return app


app = create_app()
