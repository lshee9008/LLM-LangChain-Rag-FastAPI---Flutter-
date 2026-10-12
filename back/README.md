# Blues Bot 백엔드

Python 3.10.12+ / FastAPI / LangChain Core / Chroma / SQLite.

```sh
cp -n .env.example .env
uv sync --locked
uv run uvicorn main:app --host 127.0.0.1 --port 8000
```

설정·API 명세·테스트·제한 사항은 [프로젝트 실행 안내](../README.md)를 참고하세요.
