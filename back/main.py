import asyncio
import json
import logging
from contextlib import asynccontextmanager, suppress

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse

from chain_service import ChatService
from config import Settings
from providers import LiveData
from schemas import ChatRequest, ChatResponse

logger = logging.getLogger(__name__)


def encode_event(event: str, data: dict) -> str:
    return f"event: {event}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"


def create_app(settings: Settings | None = None, service=None) -> FastAPI:
    settings = settings or Settings.from_env()

    @asynccontextmanager
    async def lifespan(app):
        async with httpx.AsyncClient(timeout=settings.provider_timeout) as client:
            app.state.chat = service or ChatService(settings, LiveData(settings, client))
            yield

    app = FastAPI(title="Chelsea FC Blues Bot API", version="0.3.0", lifespan=lifespan)
    app.add_middleware(CORSMiddleware, allow_origins=list(settings.cors_origins),
                       allow_credentials=False, allow_methods=["GET", "POST"],
                       allow_headers=["Content-Type", "Accept"])

    @app.get("/health")
    async def health():
        return {"status": "ok", "version": "0.3.0", "capabilities": {
            "chat": bool(settings.openai_api_key), "web_search": bool(settings.tavily_api_key),
            "football": bool(settings.football_api_key)}, "note": "설정 여부이며 외부 API 연결 상태를 보장하지 않습니다."}

    def reserve(request):
        if not settings.openai_api_key:
            raise HTTPException(503, "답변 서비스가 아직 설정되지 않았습니다.")
        chat = app.state.chat
        state = chat.reserve(request.session_id)
        if state:
            raise HTTPException(409 if state == "busy" else 429,
                                "이미 답변 중인 대화입니다." if state == "busy" else "요청이 많습니다. 잠시 후 다시 시도해 주세요.")
        return chat

    @app.post("/api/v1/chat", response_model=ChatResponse)
    async def chat_endpoint(request: ChatRequest):
        chat = reserve(request)

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
            chat.release(request.session_id)

    @app.post("/api/v1/chat/stream")
    async def stream_endpoint(request: ChatRequest):
        chat = reserve(request)

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
                chat.release(request.session_id)

        return StreamingResponse(events(), media_type="text/event-stream",
                                 headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})

    return app


app = create_app()
