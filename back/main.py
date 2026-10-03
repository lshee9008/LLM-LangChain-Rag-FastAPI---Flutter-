import os

from fastapi import FastAPI
from pydantic import BaseModel
from dotenv import load_dotenv

from langchain_core.documents import Document
from langchain_core.prompts import PromptTemplate

from langchain_community.vectorstores import FAISS
from langchain_openai import OpenAIEmbeddings, ChatOpenAI

from langchain_classic.chains import create_retrieval_chain
from langchain_classic.chains.combine_documents import (
    create_stuff_documents_chain,
)

load_dotenv()

app = FastAPI()

# 1. 실습용 데이터 임베딩 및 벡터 저장소 생성
sample_texts = [
    "플러터(Flutter)는 구글이 개발한 오픈소스 UI 크로스 플랫폼 프레임워크입니다.",
    "LangChain은 LLM 기반 애플리케이션 개발을 돕기 위해 만들어진 프레임워크입니다.",
    "FastAPI는 파이썬 3.6 이상을 위한 빠르고 직관적인 서버 프레임워크입니다.",
    "RAG는 데이터베이스에서 관련 정보를 검색한 후 LLM의 답변 정확도를 높이는 기술입니다."
]

docs = [
    Document(page_content=text)
    for text in sample_texts
]

# print(docs)
# [Document(metadata={}, page_content='플러터(Flutter)는 구글이 개발한 오픈소스 UI 크로스 플랫폼 프레임워크입니다.'), Document(metadata={}, page_content='LangChain은 LLM 기반 애플리케이션 개발을 돕기 위해 만들어진 프레임워크입니다.'), Document(metadata={}, page_content='FastAPI는 파이썬 3.6 이상을 위한 빠르고 직관적인 서버 프레임워크입니다.'), Document(metadata={}, page_content='RAG는 데이터베이스에서 관련 정보를 검색한 후 LLM의 답변 정확도를 높이는 기술입니다.')]

# OpenAI 임베딩 및 FAISS 벡터 DB 구축
# 벡터 데이터베이스 및 검색기(Retriever) 설정

# FAISS.from_documents:
# Document 객체 리스트(docs)를 OpenAIEmbeddings() 모델을 사용해 벡터(숫자 배열)로 변환한 뒤,
# FAISS라는 빠르고 가벼운 인메모리 벡터 DB에 저장
vectorstore = FAISS.from_documents(docs, OpenAIEmbeddings())

# as_retriever:
# 구축된 백터 DB를 LangChain 체인에서 사용할 수 있는 '검색기' 객체로 변환
# 사용자가 질문을 던지면, 이 객체가 질문과 가장 유사한 문서를 DB에서 찾아옴
retriever = vectorstore.as_retriever()
print(retriever) # 검색기 설정 상태 출력 (검색 알고리즘, 반환할 문서 개수 K 등의 기본 설정 확인 가능)

# 2. 최신 LangChain 방식(LCEL)의 RAG 체인 구성

# ChatOpenAI:
# 답변을 생성할 대형 언어 모델(LLM)을 정의
# temperature=0으로 설정하면 모델이 창의적인 답변보다는 일관되고 사실적인(결정론적) 답변을 생성하도록 제한
llm = ChatOpenAI(model="gpt-3.5-turbo", temperature=0)

# PromptTemplate.from_template:
# 하나의 긴 텍스트 문자열(String) 형태로 프롬프트를 구성
# {context}에는 retriever가 찾아온 문서 내용이 들어가고, {input}에는 사요자의 질문이 들어감
prompt = PromptTemplate.from_template(
    "다음 문맥(context)을 바탕으로 질문(Question)에 답하세요.\n\n문맥: {context}\n\n 질문: {input}]n답변:"
)

# create_stuff_documents_chain:
# 찾아온 여러 개의 문서(Documents)를 프롬프트이 {context} 변수에 "그대로 쑤셔 넣는(stuff)" 체인임
# 문서 내용과 프롬프트를 합쳐서 LLM에게 전달하는 역할을 함
combine_docs_chain = create_stuff_documents_chain(llm, prompt)

# create_retrieval_chain:
# 검색(retriever)과 문서 결합(combine_docs_chain)을 하나의 파이프라인으로 연결
# 체인을 실행(invoke)하면 -> 사용자의 질문 수신 -> retirieval가 관련 문서 검색 
# -> combine_docs_chain이 프롬프트 완성 -> LLM이 최종 답변 생성의 순서로 자동 실행

retrieval_chain = create_retrieval_chain(retriever, combine_docs_chain)


# 3. FastAPI 엔드포인트 라우터 정의

# 데이터 검증 모델 정의 (Pydantic)
# BaseModel을 상속받아 클라이언트(플러터 앱)와 서버(FastAPI)가 주고받을 데이터의 '형태(스키마)'를 정의
# 이 클래스들은 데이터가 올바른 타입(str, int 등)인지 자동으로 검사(Validation) 해 줌
class QueryRequest(BaseModel):
    # 클라이언트가 서버로 보낼 때 사용할 형식
    # JSON 형태의 {"query": "플러터가 뭐야?"} 데이터가 들어올 것을 예상하고,
    # 'query'라는 키값과 문자열(str) 타입의 데이터를 필수로 요구함
    query: str

class QueryResponse(BaseModel):
    # 서버가 작업을 마치고 클라이언트에게 돌려줄 응답의 형식
    # JSON 형태의 {"answer": "플러터는 구글이 개발한..."} 형태로 반환하겠다고 약속
    answer: str 
    
@app.post("/ask", response_model=QueryResponse)
async def ask_question(request: QueryRequest):
    # async def: 비동기 함수로 선언
    # LLM이 답변을 생성하는 데 몇 초가 걸리더라도, 서버가 멈추지 않고 다른 사용자의 요청을 동시에 받을 수 있게 해줌
    
    # retrieval_chain.invoke: 준비해둔 RAG 파이프라인을 가동
    # 앞서 정의한 PromptTemplate에서 {input}이라는 변수를 사용했기 때문에,
    # 딕셔너리 형태로 {"input": request.query (사용자 질문)}을 짝지어 넘겨줌
    result = retrieval_chain.invoke({"input": request.query})
    
    # 체인이 성공적으로 완료되면 result 변수에는 여러 정보가 딕셔너리 형태로 담긴다
    # 예: {"input": "...", "context": [검색된 문서들], "answer": "최종 생성된 답변"}
    # 여기서는 플러터 앱이 필요로 하는 최종 답변(result["answer"])만 추출
    
    # QueryResponse 형식에 맞춰 객체를 생성하여 반환하면, 
    # FastAPI가 이를 자동으로 JSON 포맷({"answer": "..."})으로 변환하여 플러터 앱에 전송
    return QueryResponse(answer=result["answer"])