import os
from langchain_community.document_loaders import TextLoader, PyPDFLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_openai import OpenAIEmbeddings
from langchain_community.vectorstores import Chroma

PERSIST_DIRECTORY = "./chroma_db"
embeddings = OpenAIEmbeddings()

def init_chelsea_vecotr_db(file_path: str = "./data/chelsea_info.txt"):
    """첼시 구단 문서를 읽고 Vector DB(ChromaDB)에 저장"""
    if file_path.endswith('.pdf'):
        loader = PyPDFLoader(file_path)
    else:
        loader = TextLoader(file_path, encoding='utf-8')
    
    documents = loader.load()
    
    # 텍스트 청크 분할
    text_splitter = RecursiveCharacterTextSplitter(chunk_size=400, chunk_overlap=40)
    docs = text_splitter.split_documents(documents)
    
    # Chroma DB 인덱싱
    vectorstore = Chroma.from_documents(
        documents=docs,
        embedding=embeddings,
        persist_directory=PERSIST_DIRECTORY
    )
    return vectorstore

def get_chelsea_retriever():
    """저장된 Vector DB에서 검색기(Retriever) 추출"""
    vectorstore = Chroma(
        persist_directory=PERSIST_DIRECTORY,
        embedding_function=embeddings
    )
    
    # 상위 3개 유사 문맥 추출
    return vectorstore.as_retriever(search_kwargs={"k": 3})

