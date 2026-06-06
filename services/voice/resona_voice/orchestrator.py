from __future__ import annotations

import asyncio
import re
from dataclasses import dataclass, field

from .protocols import Clock, LLMProvider, TTSProvider
from .tools import ToolRegistry
from .types import LatencySpan, LLMResponse, TurnResult


def split_clauses(text: str) -> list[str]:
    parts = re.split(r"(?<=[.!?])\s+", text.strip())
    return [p for p in parts if p]


@dataclass
class Orchestrator:
    llm: LLMProvider
    tts: TTSProvider
    tools: ToolRegistry
    clock: Clock
    system_prompt: str = ""
    max_tool_rounds: int = 3
    barge_in: asyncio.Event | None = None
    _barge: asyncio.Event = field(init=False)

    def __post_init__(self) -> None:
        self._barge = self.barge_in or asyncio.Event()

    def interrupt(self) -> None:
        self._barge.set()

    async def _llm(self, messages: list[dict], spans: list[LatencySpan]) -> LLMResponse:
        t = self.clock.now()
        resp = await self.llm.complete(messages, self.tools.schemas())
        spans.append(LatencySpan("llm", self.clock.now() - t))
        return resp

    async def handle_user_turn(
        self, user_text: str, history: list[dict] | None = None
    ) -> TurnResult:
        self._barge.clear()
        spans: list[LatencySpan] = []
        t_turn = self.clock.now()

        messages: list[dict] = []
        if self.system_prompt:
            messages.append({"role": "system", "content": self.system_prompt})
        messages.extend(history or [])
        messages.append({"role": "user", "content": user_text})

        resp = await self._llm(messages, spans)
        rounds = 0
        while resp.tool_calls and rounds < self.max_tool_rounds:
            for tc in resp.tool_calls:
                t = self.clock.now()
                result = await self.tools.dispatch(tc.name, tc.arguments)
                spans.append(LatencySpan("tool", self.clock.now() - t))
                messages.append({"role": "tool", "name": tc.name, "content": result})
            resp = await self._llm(messages, spans)
            rounds += 1

        text = resp.text or ""

        audio_chunks = 0
        interrupted = False
        t_tts = self.clock.now()
        for clause in split_clauses(text):
            if self._barge.is_set():
                interrupted = True
                break
            async for _chunk in self.tts.synthesize(clause):
                if self._barge.is_set():
                    interrupted = True
                    break
                audio_chunks += 1
            if interrupted:
                break
        spans.append(LatencySpan("tts", self.clock.now() - t_tts))
        spans.append(LatencySpan("turn", self.clock.now() - t_turn))

        return TurnResult(
            text=text, spans=spans, interrupted=interrupted, audio_chunks=audio_chunks
        )
