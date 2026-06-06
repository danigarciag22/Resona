from __future__ import annotations

from typing import Awaitable, Callable

from .protocols import Calendar, Embedder, KnowledgeSearch

ToolFn = Callable[..., Awaitable[str]]


class ToolRegistry:
    def __init__(self) -> None:
        self._fns: dict[str, ToolFn] = {}
        self._schemas: list[dict] = []

    def register(self, name: str, fn: ToolFn, schema: dict) -> None:
        self._fns[name] = fn
        self._schemas.append(schema)

    def schemas(self) -> list[dict]:
        return self._schemas

    async def dispatch(self, name: str, arguments: dict) -> str:
        fn = self._fns.get(name)
        if fn is None:
            return f"error: unknown tool {name}"
        return await fn(**arguments)


def make_book_appointment(calendar: Calendar) -> ToolFn:
    async def book_appointment(*, date: str, time: str, name: str = "") -> str:
        slot = await calendar.book(date=date, time=time, name=name)
        return f"booked {slot}"

    return book_appointment


def make_search_knowledge_base(
    embedder: Embedder, search: KnowledgeSearch, kb_id: str
) -> ToolFn:
    async def search_knowledge_base(*, query: str) -> str:
        vector = await embedder.embed(query)
        hits = await search.match(vector, kb_id)
        return "\n".join(h["content"] for h in hits) or "no results"

    return search_knowledge_base
