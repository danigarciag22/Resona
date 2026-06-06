from __future__ import annotations

from typing import AsyncIterator, Protocol

from .types import LLMResponse


class LLMProvider(Protocol):
    async def complete(
        self, messages: list[dict], tools: list[dict]
    ) -> LLMResponse: ...


class TTSProvider(Protocol):
    def synthesize(self, text: str) -> AsyncIterator[bytes]: ...


class Clock(Protocol):
    def now(self) -> float: ...


class Embedder(Protocol):
    async def embed(self, text: str) -> list[float]: ...


class KnowledgeSearch(Protocol):
    async def match(self, embedding: list[float], kb_id: str) -> list[dict]: ...


class Calendar(Protocol):
    async def book(self, **kwargs) -> str: ...
