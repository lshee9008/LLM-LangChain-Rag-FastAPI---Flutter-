import os

# 문서 파일을 읽기 위한 Loader
# TextLoader : txt 파일을 읽음
# PyPDFLoader : pdf 파일을 읽음
from langchain_community.document_loaders import TextLoader, PyPDFLoader

# 긴 문서를 일정한 크기의 작은 청크(chunk)로 분할하기 위한 도구
from langchain_text_splitters import RecursiveCharacterTextSplitter

# OpenAI의 Embedding 모델 사용
# 텍스트를 숫자 벡터(Vector) 형태로 변환할 때 사용
from langchain_openai import OpenAIEmbeddings

# 벡터 데이터베이스인 ChromaDB 사용
# Embedding된 문서 벡터를 저장하고,
# 사용자의 질문과 의미적으로 비슷한 문서를 검색할 때 사용
from langchain_community.vectorstores import Chroma


# ---------------------------------------------------------
# Vector DB가 저장될 폴더 경로
# ---------------------------------------------------------
# ChromaDB에 저장된 벡터 데이터를
# 프로그램을 종료한 이후에도 유지하기 위해 사용하는 디렉터리
#
# 프로젝트 구조 예시
#
# back/
# ├── data/
# │   └── chelsea_info.txt
# ├── chroma_db/
# │   └── ...
# └── vector_db.py
#
# 처음 실행하면 chroma_db 폴더가 생성되고
# 이후에는 이곳에 저장된 Vector DB를 다시 사용할 수 있음
# ---------------------------------------------------------
PERSIST_DIRECTORY = "./chroma_db"


# ---------------------------------------------------------
# OpenAI Embedding 모델 생성
# ---------------------------------------------------------
# Embedding이란?
#
# "첼시는 프리미어리그 축구팀입니다."
#
# 같은 텍스트를 LLM이 직접 비교하는 것이 아니라
# 다음과 같은 숫자 배열(Vector)로 변환하는 과정
#
# 예:
# [0.231, -0.142, 0.831, ...]
#
# 이렇게 변환하면 두 문장의 의미가 얼마나 비슷한지
# 수학적으로 계산할 수 있음
#
# 예:
#
# 질문
# "첼시는 어느 리그 팀이야?"
#
# 문서
# "첼시는 잉글랜드 프리미어리그 소속 구단입니다."
#
# → 두 벡터가 서로 가까움
# → 관련 문서라고 판단
# ---------------------------------------------------------
embeddings = OpenAIEmbeddings()


def init_chelsea_vecotr_db(file_path: str = "./data/chelsea_info.txt"):
    """
    첼시 관련 문서를 읽은 뒤
    문서를 작은 Chunk로 나누고,
    각 Chunk를 Embedding하여
    Chroma Vector DB에 저장하는 함수

    처리 과정

    파일
      ↓
    Document 객체
      ↓
    Chunk 분할
      ↓
    Embedding
      ↓
    ChromaDB 저장

    Parameters
    ----------
    file_path : str
        읽을 문서의 경로

        기본값:
        ./data/chelsea_info.txt

        txt와 pdf 파일을 지원

    Returns
    -------
    vectorstore : Chroma
        생성된 Chroma Vector Store 객체
    """

    # -----------------------------------------------------
    # 1. 파일 종류에 따라 Loader 선택
    # -----------------------------------------------------
    # 파일 확장자가 .pdf이면 PyPDFLoader를 사용
    #
    # 예:
    # "./data/chelsea_history.pdf"
    #
    # PDF의 경우 페이지 단위로 Document가 생성될 수 있음
    # -----------------------------------------------------
    if file_path.endswith('.pdf'):
        loader = PyPDFLoader(file_path)

    # -----------------------------------------------------
    # PDF가 아니라면 일반 텍스트 파일로 간주
    # -----------------------------------------------------
    # TextLoader를 사용하여 UTF-8 형식의 텍스트 파일을 읽음
    #
    # 예:
    # "./data/chelsea_info.txt"
    #
    # encoding='utf-8'
    # → 한글이 포함된 txt 파일에서 인코딩 문제가 발생하지 않도록 설정
    # -----------------------------------------------------
    else:
        loader = TextLoader(
            file_path,
            encoding='utf-8'
        )

    # -----------------------------------------------------
    # 2. 실제 문서 읽기
    # -----------------------------------------------------
    # loader.load()를 실행하면
    # 파일 내용을 LangChain의 Document 객체로 변환
    #
    # 반환 예시:
    #
    # [
    #     Document(
    #         page_content="첼시 FC는 런던을 연고로...",
    #         metadata={"source": "./data/chelsea_info.txt"}
    #     )
    # ]
    #
    # Document의 핵심 구성
    #
    # page_content
    # → 실제 문서의 텍스트
    #
    # metadata
    # → 파일 경로, PDF 페이지 등의 추가 정보
    # -----------------------------------------------------
    documents = loader.load()


    # -----------------------------------------------------
    # 3. 긴 문서를 작은 Chunk로 나누기
    # -----------------------------------------------------
    # RAG에서는 문서 전체를 그대로 Vector DB에 넣기보다는
    # 작은 단위로 나누는 것이 일반적
    #
    # 이유:
    #
    # 문서 전체가 너무 길면
    # 사용자의 질문과 정확히 관련 있는 부분을 찾기 어려움
    #
    # 예:
    #
    # 원본 문서
    # ┌─────────────────────────────┐
    # │ 첼시 창단 역사              │
    # │ 선수 정보                   │
    # │ 감독 정보                   │
    # │ 우승 기록                   │
    # └─────────────────────────────┘
    #
    # ↓ Chunk 분할
    #
    # Chunk 1 : 첼시 창단 역사
    # Chunk 2 : 선수 정보
    # Chunk 3 : 감독 정보
    # Chunk 4 : 우승 기록
    #
    # 그러면
    #
    # "첼시 감독이 누구야?"
    #
    # 질문이 들어왔을 때
    # 감독 관련 Chunk를 더 정확하게 찾을 수 있음
    # -----------------------------------------------------
    text_splitter = RecursiveCharacterTextSplitter(

        # 하나의 Chunk에 들어갈 최대 문자 수
        #
        # 대략 400자 단위로 문서를 나눔
        chunk_size=400,

        # Chunk 사이에 40자의 중복을 둠
        #
        # 예:
        #
        # Chunk 1
        # ---------------------
        # 첼시는 런던에 위치...
        # 감독은 ...
        #
        # Chunk 2
        # ---------------------
        # 감독은 ...
        # 주요 선수는 ...
        #
        # 이렇게 앞뒤 Chunk의 문맥이 끊기는 것을 방지
        chunk_overlap=40
    )


    # -----------------------------------------------------
    # 4. Document를 실제 Chunk 단위로 분할
    # -----------------------------------------------------
    # documents
    #
    # [
    #   긴 Document
    # ]
    #
    # ↓
    #
    # docs
    #
    # [
    #   Document(chunk1),
    #   Document(chunk2),
    #   Document(chunk3),
    #   ...
    # ]
    #
    # 각 Chunk 역시 LangChain의 Document 객체
    # -----------------------------------------------------
    docs = text_splitter.split_documents(documents)


    # -----------------------------------------------------
    # 5. Chunk → Embedding → ChromaDB 저장
    # -----------------------------------------------------
    #
    # 내부적으로 다음 과정이 수행됨
    #
    # docs
    #
    # "첼시는 런던을 연고로..."
    #
    #      ↓
    #
    # OpenAIEmbeddings
    #
    #      ↓
    #
    # [0.123, -0.821, 0.322, ...]
    #
    #      ↓
    #
    # ChromaDB 저장
    #
    #
    # documents=docs
    # → 저장할 Document Chunk 목록
    #
    # embedding=embeddings
    # → 어떤 Embedding 모델을 사용할지 지정
    #
    # persist_directory
    # → Vector DB 데이터를 실제 디스크에 저장할 위치
    # -----------------------------------------------------
    vectorstore = Chroma.from_documents(
        documents=docs,
        embedding=embeddings,
        persist_directory=PERSIST_DIRECTORY
    )


    # -----------------------------------------------------
    # 생성된 Vector Store 객체 반환
    # -----------------------------------------------------
    # 이 객체를 통해 나중에
    #
    # similarity_search()
    #
    # 또는
    #
    # as_retriever()
    #
    # 등을 사용할 수 있음
    # -----------------------------------------------------
    return vectorstore



def get_chelsea_retriever():
    """
    기존에 저장되어 있는 Chroma Vector DB를 불러온 뒤
    LangChain Retriever로 변환하는 함수

    Retriever는 사용자의 질문과 의미적으로 비슷한
    Document를 Vector DB에서 검색하는 역할을 함

    처리 과정

    사용자 질문
        ↓
    Embedding
        ↓
    ChromaDB 검색
        ↓
    관련 문서 Top 3
        ↓
    LLM에게 전달
    """

    # -----------------------------------------------------
    # 1. 기존 Chroma Vector DB 불러오기
    # -----------------------------------------------------
    # init_chelsea_vecotr_db()에서 생성해둔
    #
    # ./chroma_db
    #
    # 디렉터리의 Vector DB를 다시 로드
    #
    # persist_directory
    # → DB가 저장된 위치
    #
    # embedding_function
    # → 검색 질문도 문서와 동일한 Embedding 모델을 사용해야 함
    #
    # 예:
    #
    # 저장 당시
    #
    # "첼시는 런던에 위치..."
    #        ↓
    # OpenAIEmbeddings
    #
    #
    # 검색 당시
    #
    # "첼시 연고지가 어디야?"
    #        ↓
    # OpenAIEmbeddings
    #
    # 같은 Embedding 모델 공간에서
    # 두 벡터의 유사도를 비교함
    # -----------------------------------------------------
    vectorstore = Chroma(
        persist_directory=PERSIST_DIRECTORY,
        embedding_function=embeddings
    )


    # -----------------------------------------------------
    # 2. Vector Store를 Retriever로 변환
    # -----------------------------------------------------
    #
    # VectorStore
    # → 실제 벡터를 저장하고 검색하는 DB
    #
    # Retriever
    # → LangChain이 VectorStore를 쉽게 사용할 수 있도록 만든 검색 인터페이스
    #
    #
    # search_kwargs={"k": 3}
    #
    # 사용자의 질문과 가장 비슷한 문서
    # 상위 3개를 반환
    #
    # 예:
    #
    # 질문:
    # "첼시는 몇 번 우승했어?"
    #
    # 검색 결과:
    #
    # Document 1 : 프리미어리그 우승 기록
    # Document 2 : 챔피언스리그 우승 기록
    # Document 3 : FA컵 우승 기록
    #
    # 이 Document들이 이후 LLM의 Context로 전달됨
    # -----------------------------------------------------
    return vectorstore.as_retriever(
        search_kwargs={
            "k": 3
        }
    )