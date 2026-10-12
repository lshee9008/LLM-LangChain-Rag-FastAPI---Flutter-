"""Lazy, idempotent Chroma indexing. The Phase 2 database is preserved."""
import asyncio
import hashlib
from datetime import datetime, timezone

from langchain_chroma import Chroma
from langchain_core.documents import Document
from langchain_openai import OpenAIEmbeddings
from langchain_text_splitters import RecursiveCharacterTextSplitter

from config import Settings
from schemas import Evidence, Source


class ChelseaKnowledge:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.store = None
        self.lock = asyncio.Lock()

    def _initialize(self):
        embeddings = OpenAIEmbeddings(
            api_key=self.settings.openai_api_key, model=self.settings.embedding_model,
            request_timeout=self.settings.provider_timeout, max_retries=1,
        )
        name = "chelsea_" + hashlib.sha256(self.settings.embedding_model.encode()).hexdigest()[:12]
        store = Chroma(collection_name=name, embedding_function=embeddings,
                       persist_directory=str(self.settings.chroma_dir))
        documents = [Document(page_content=p.read_text(encoding="utf-8"),
                              metadata={"source": p.name})
                     for p in sorted(self.settings.data_dir.glob("*.txt"))]
        chunks = RecursiveCharacterTextSplitter(chunk_size=600, chunk_overlap=80).split_documents(documents)
        ids = [hashlib.sha256((d.metadata["source"] + d.page_content).encode()).hexdigest()
               for d in chunks]
        existing = set(store.get()["ids"])
        pending = [(i, d) for i, d in zip(ids, chunks) if i not in existing]
        # Add first so a failed embedding request doesn't destroy the previous index.
        if pending:
            store.add_documents([d for _, d in pending], ids=[i for i, _ in pending])
        stale = existing - set(ids)
        if stale:
            store.delete(ids=list(stale))
        self.store = store

    async def search(self, query: str) -> Evidence:
        if not self.settings.openai_api_key:
            return Evidence(warnings=["구단 문서 검색 기능이 아직 연결되지 않았습니다."])
        try:
            async with self.lock:
                if self.store is None:
                    await asyncio.to_thread(self._initialize)
            docs = await self.store.asimilarity_search(query, k=3)
            now = datetime.now(timezone.utc).isoformat()
            return Evidence(sources=[Source(kind="document", title=d.metadata.get("source", "구단 문서"),
                                           excerpt=d.page_content, retrieved_at=now) for d in docs])
        except Exception:
            return Evidence(warnings=["구단 문서 검색에 실패했습니다. 서버 설정과 네트워크를 확인해 주세요."])
