from __future__ import annotations

import asyncio
from typing import AsyncIterator

from .types import LLMResponse


class ManualClock:
    """Monotonic fake clock; each call advances by `step` so span diffs are positive."""

    def __init__(self, step: float = 1.0) -> None:
        self._t = 0.0
        self._step = step

    def now(self) -> float:
        self._t += self._step
        return self._t


class FakeLLM:
    def __init__(self, responses: list[LLMResponse]) -> None:
        self._responses = list(responses)
        self.calls: list[list[dict]] = []

    async def complete(self, messages: list[dict], tools: list[dict]) -> LLMResponse:
        self.calls.append(list(messages))
        return self._responses.pop(0)


class FakeTTS:
    def __init__(self, chunks_per_clause: int = 2) -> None:
        self.chunks_per_clause = chunks_per_clause
        self.synth_calls: list[str] = []

    async def synthesize(self, text: str) -> AsyncIterator[bytes]:
        self.synth_calls.append(text)
        for _ in range(self.chunks_per_clause):
            yield b"audio"


class BargeInFakeTTS:
    """Sets `event` after yielding `fire_after_chunks` chunks, simulating the caller
    talking over the agent mid-utterance."""

    def __init__(
        self,
        event: asyncio.Event,
        fire_after_chunks: int = 1,
        chunks_per_clause: int = 2,
    ) -> None:
        self.event = event
        self.fire_after = fire_after_chunks
        self.chunks_per_clause = chunks_per_clause
        self.count = 0

    async def synthesize(self, text: str) -> AsyncIterator[bytes]:
        for _ in range(self.chunks_per_clause):
            self.count += 1
            yield b"audio"
            if self.count >= self.fire_after:
                self.event.set()
