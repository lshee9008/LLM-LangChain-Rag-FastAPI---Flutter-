from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import os
from dotenv import load_dotenv # 추가

# .env 파일에서 환경 변수 불러오기
load_dotenv()

from rag_service import init_chelsea_vector_db
from chain_service import chelsea_chat_chain

app = FastAPI(title="Chelsea FC Real-time RAG API")

# Flutter 통신을 위한 CORS 허용
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class ChatRequest(BaseModel):
    session_id: str
    question: str

class ChatResponse(BaseModel):
    session_id: str
    answer: str

@app.on_event("startup")
def startup_event():
    # 서버 스타트업 시 문서 DB 생성 (최초 1회)
    if not os.path.exists("./chroma_db"):
        print("Initializing Chelsea Vector DB...")
        init_chelsea_vector_db()

@app.post("/api/v1/chat", response_model=ChatResponse)
async def chat_endpoint(request: ChatRequest):
    try:
        response = chelsea_chat_chain.invoke(
            {"input": request.question},
            config={"configurable": {"session_id": request.session_id}}
        )
        return ChatResponse(
            session_id=request.session_id,
            answer=response["answer"]
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))