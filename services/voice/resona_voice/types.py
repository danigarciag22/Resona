from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class ToolCall:
    name: str
    arguments: dict


@dataclass
class LLMResponse:
    text: str | None = None
    tool_calls: list[ToolCall] = field(default_factory=list)


@dataclass
class LatencySpan:
    stage: str  # "llm" | "tool" | "tts" | "turn"
    ms: float


@dataclass
class TurnResult:
    text: str
    spans: list[LatencySpan]
    interrupted: bool = False
    audio_chunks: int = 0
