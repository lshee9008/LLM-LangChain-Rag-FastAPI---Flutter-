"""Bounded, asynchronous read-only providers, with short-lived result caching."""
import json
import time
from datetime import datetime, timezone
from typing import Literal
from urllib.parse import urlencode, urlsplit

import httpx

from config import Settings
from schemas import Evidence, Source


class ProviderError(Exception):
    pass


def safe_url(value: str) -> str | None:
    try:
        parsed = urlsplit(value)
        if parsed.scheme in {"http", "https"} and parsed.hostname and not parsed.username:
            return value
    except ValueError:
        pass
    return None


class LiveData:
    def __init__(self, settings: Settings, client: httpx.AsyncClient):
        self.settings, self.client = settings, client
        self.cache: dict[str, tuple[float, Evidence]] = {}

    async def _cached(self, key, fetch):
        entry = self.cache.get(key)
        if entry and entry[0] > time.monotonic():
            result = entry[1].model_copy(deep=True)
            for source in result.sources:
                source.cached = True
            return result
        try:
            result = await fetch()
        except (httpx.HTTPError, ValueError, KeyError, TypeError, ProviderError):
            return Evidence(warnings=["외부 데이터 제공처에서 정보를 가져오지 못했습니다. 잠시 후 다시 시도해 주세요."])
        if result.sources:
            if len(self.cache) >= 128:
                self.cache.pop(next(iter(self.cache)))
            self.cache[key] = (time.monotonic() + self.settings.cache_ttl, result.model_copy(deep=True))
        return result

    async def web_search(self, query: str, recent: bool = True) -> Evidence:
        if not self.settings.tavily_api_key:
            return Evidence(warnings=["최신 뉴스 검색 기능이 아직 연결되지 않았습니다."])

        async def fetch():
            body = {"query": query[:500], "max_results": 5, "search_depth": "basic",
                    "topic": "news" if recent else "general", "include_answer": False,
                    "include_raw_content": False}
            if recent:
                body["time_range"] = "week"
            response = await self.client.post("https://api.tavily.com/search", json=body,
                                             headers={"Authorization": f"Bearer {self.settings.tavily_api_key}"})
            response.raise_for_status()
            data = response.json()
            now = datetime.now(timezone.utc).isoformat()
            sources = []
            for item in data.get("results", []):
                url = safe_url(item.get("url", ""))
                if url and item.get("content"):
                    sources.append(Source(kind="web", title=item.get("title", "웹 검색"), url=url,
                                          excerpt=item["content"][:1800], retrieved_at=now,
                                          published_at=item.get("published_date")))
            return Evidence(sources=sources, warnings=[] if sources else ["검색 기간에 해당하는 웹 검색 결과가 없습니다."])

        return await self._cached(f"web:{recent}:{query}", fetch)

    async def _football(self, endpoint: str, params: dict) -> list:
        response = await self.client.get(f"https://v3.football.api-sports.io/{endpoint}",
                                         params=params, headers={"x-apisports-key": self.settings.football_api_key})
        response.raise_for_status()
        data = response.json()
        # API-Football also reports quota/plan failures in HTTP 200 responses.
        if data.get("errors"):
            raise ProviderError("provider rejected request")
        result = data.get("response", [])
        if not isinstance(result, list):
            raise ProviderError("invalid response")
        return result

    async def football(self, kind: Literal["results", "fixtures", "standings", "player", "player_recent"],
                       player: str = "Cole Palmer", season: int | None = None) -> Evidence:
        if not self.settings.football_api_key:
            return Evidence(warnings=["축구 통계 조회 기능이 아직 연결되지 않았습니다."])

        async def fetch():
            current = datetime.now(timezone.utc)
            year = season if season is not None else current.year - (current.month < 7)
            if kind == "player_recent":
                aliases = {"콜파머": "Cole Palmer", "콜 파머": "Cole Palmer", "파머": "Cole Palmer"}
                name = aliases.get(player.strip(), player.strip())
                names = {name.casefold()}
                if name == "Cole Palmer":
                    names.add("c. palmer")
                endpoint, params = "fixtures", {"team": 49, "last": 5, "timezone": "Asia/Seoul"}
                fixtures = await self._football(endpoint, params)
                records = []
                for fixture in fixtures[:5]:
                    teams = await self._football("fixtures/players", {"fixture": fixture["fixture"]["id"], "team": 49})
                    for team in teams:
                        for entry in team.get("players", []):
                            if entry["player"]["name"].casefold() in names:
                                records.append({"fixture_id": fixture["fixture"]["id"],
                                                "date": fixture["fixture"]["date"], "teams": fixture["teams"],
                                                "goals": fixture["goals"], "player": entry["player"],
                                                "statistics": entry["statistics"]})
                label = f"{name} 첼시 최근 5경기 중 제공된 경기별 선수 기록 (없음은 미출전 확정 아님)"
            elif kind in {"results", "fixtures"}:
                endpoint = "fixtures"
                params = {"team": 49, "last" if kind == "results" else "next": 5,
                          "timezone": "Asia/Seoul"}
                rows = await self._football(endpoint, params)
                records = [{"date": r["fixture"]["date"], "status": r["fixture"]["status"],
                            "competition": r["league"]["name"], "teams": r["teams"], "goals": r["goals"]}
                           for r in rows]
                label = "첼시 최근 경기 결과" if kind == "results" else "첼시 다음 경기 일정"
            elif kind == "standings":
                endpoint, params = "standings", {"league": 39, "season": year}
                rows = await self._football(endpoint, params)
                records = [r for league in rows for group in league["league"]["standings"] for r in group]
                label = f"{year}/{year + 1} 프리미어리그 순위"
            else:
                aliases = {"콜파머": "Cole Palmer", "콜 파머": "Cole Palmer", "파머": "Cole Palmer"}
                name = aliases.get(player.strip(), player.strip())
                endpoint, params = "players", {"team": 49, "season": year, "search": name.split()[-1]}
                rows = await self._football(endpoint, params)
                normalize = lambda s: "".join(c for c in s.casefold() if c.isalnum())
                records = []
                for r in rows:
                    p = r["player"]
                    names = [p.get("name", ""), f"{p.get('firstname', '')} {p.get('lastname', '')}"]
                    if normalize(name) in map(normalize, names):
                        records.append({"player": p["name"], "season": year, "statistics": r["statistics"]})
                label = f"{name} {year}/{year + 1} 시즌 누적 통계 (경기별 기록 아님)"
            if not records:
                return Evidence(warnings=["요청한 시즌·선수의 통계가 제공되지 않았습니다. 선수 영문명이나 시즌을 지정해 다시 질문해 주세요."])
            url = f"https://v3.football.api-sports.io/{endpoint}?{urlencode(params)}"
            return Evidence(sources=[Source(kind="football", title=label, url=url,
                                           excerpt=json.dumps(records, ensure_ascii=False)[:24000],
                                           retrieved_at=current.isoformat())])

        return await self._cached(f"football:{kind}:{player}:{season}", fetch)
