# Voice Agent Core (Plan 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the provider-agnostic real-time voice-agent core — a turn orchestrator with tool-calling, barge-in interruption, and per-stage latency spans, plus a FastAPI/Twilio control plane — fully unit-tested with deterministic fakes and no external credentials.

**Architecture:** A Python service `services/voice/` whose `Orchestrator` depends only on small `Protocol` interfaces (`LLMProvider`, `TTSProvider`, `Clock`, `Embedder`, `KnowledgeSearch`, `Calendar`). The turn loop calls the LLM (with a tool-dispatch loop), then streams the reply through TTS clause-by-clause while watching a barge-in `asyncio.Event` that cancels in-flight speech. Every stage records a `LatencySpan` (the documented latency budget, measured). Real Deepgram/Anthropic/Cartesia adapters and the Twilio Media Stream WebSocket are **Plan 2b** (they need API keys); this plan ships the logic + fakes so the behavior is proven now.

**Tech Stack:** Python 3.12+ (system has 3.14), FastAPI, Uvicorn, pytest, pytest-asyncio (`asyncio_mode=auto`), httpx (TestClient). No audio/native deps, no provider SDKs in this slice.

> **Why fakes, not Pipecat, in this slice:** a real call needs paid telephony + STT/LLM/TTS keys that aren't available. The design's cascaded pipeline logic (endpointing→LLM→TTS, barge-in, overlap, latency budget) is exactly what we encode and test here behind protocols. Plan 2b wires the production transport (Twilio Media Streams) and provider adapters to these same protocols.

---

## File Structure

```
services/voice/
  pyproject.toml
  .env.example
  resona_voice/
    __init__.py
    config.py            # Settings from env (media stream url + provider keys for 2b)
    types.py             # dataclasses: ToolCall, LLMResponse, LatencySpan, TurnResult
    protocols.py         # LLMProvider, TTSProvider, Clock, Embedder, KnowledgeSearch, Calendar
    fakes.py             # FakeLLM, FakeTTS, BargeInFakeTTS, ManualClock, + tool fakes
    tools.py             # ToolRegistry + book_appointment / search_knowledge_base factories
    orchestrator.py      # turn loop: LLM + tool loop, TTS streaming, barge-in, spans
    twiml.py             # connect_stream_twiml()
    app.py               # FastAPI: /health, POST /twilio/voice -> TwiML
  tests/
    test_app.py
    test_orchestrator.py
    test_tools.py
```

---

## Task 1: Python service scaffold + health endpoint (TDD)

**Files:**
- Create: `services/voice/pyproject.toml`, `services/voice/.env.example`
- Create: `services/voice/resona_voice/__init__.py`, `config.py`, `app.py`
- Test: `services/voice/tests/test_app.py`

- [ ] **Step 1: Write `pyproject.toml`**

```toml
[project]
name = "resona-voice"
version = "0.0.0"
description = "Resona real-time voice agent core"
requires-python = ">=3.12"
dependencies = [
  "fastapi>=0.115",
  "uvicorn[standard]>=0.30",
]

[project.optional-dependencies]
dev = [
  "pytest>=8",
  "pytest-asyncio>=0.23",
  "httpx>=0.27",
]

[tool.pytest.ini_options]
asyncio_mode = "auto"
testpaths = ["tests"]

[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.build_meta"

[tool.setuptools.packages.find]
include = ["resona_voice*"]
```

- [ ] **Step 2: Create the package + config**

`services/voice/resona_voice/__init__.py`:
```python
```
(empty file)

`services/voice/resona_voice/config.py`:
```python
import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    media_stream_url: str = os.getenv("MEDIA_STREAM_URL", "wss://localhost/media")
    # Provider keys are consumed by the real adapters in Plan 2b.
    deepgram_api_key: str = os.getenv("DEEPGRAM_API_KEY", "")
    anthropic_api_key: str = os.getenv("ANTHROPIC_API_KEY", "")
    cartesia_api_key: str = os.getenv("CARTESIA_API_KEY", "")


settings = Settings()
```

`services/voice/.env.example`:
```
MEDIA_STREAM_URL=wss://your-host/media
DEEPGRAM_API_KEY=
ANTHROPIC_API_KEY=
CARTESIA_API_KEY=
```

- [ ] **Step 3: Write the failing test**

`services/voice/tests/test_app.py`:
```python
from fastapi.testclient import TestClient

from resona_voice.app import app

client = TestClient(app)


def test_health_ok():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}
```

- [ ] **Step 4: Create venv, install, run test (expect fail)**

```bash
cd services/voice
python3 -m venv .venv
. .venv/bin/activate
pip install -e ".[dev]"
pytest -q
```
Expected: FAIL — `resona_voice.app` has no `app` yet (ImportError).

- [ ] **Step 5: Implement `app.py`**

`services/voice/resona_voice/app.py`:
```python
from fastapi import FastAPI

app = FastAPI(title="Resona Voice")


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}
```

- [ ] **Step 6: Run test (expect pass)**

Run: `cd services/voice && . .venv/bin/activate && pytest -q`
Expected: 1 passed.

- [ ] **Step 7: Commit**

```bash
git add services/voice/pyproject.toml services/voice/.env.example services/voice/resona_voice services/voice/tests/test_app.py
git commit -m "feat(voice): scaffold FastAPI voice service with health check"
```

---

## Task 2: Core types + protocols + fakes

**Files:**
- Create: `services/voice/resona_voice/types.py`, `protocols.py`, `fakes.py`

No standalone test — these are exercised by Tasks 3–4. (A trivial import is verified by the next task's red run.)

- [ ] **Step 1: `types.py`**

```python
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
```

- [ ] **Step 2: `protocols.py`**

```python
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
```

- [ ] **Step 3: `fakes.py`**

```python
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
        self, event: asyncio.Event, fire_after_chunks: int = 1, chunks_per_clause: int = 2
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
```

- [ ] **Step 4: Commit**

```bash
git add services/voice/resona_voice/types.py services/voice/resona_voice/protocols.py services/voice/resona_voice/fakes.py
git commit -m "feat(voice): core types, provider protocols, and test fakes"
```

---

## Task 3: Orchestrator — basic turn + latency spans (TDD)

**Files:**
- Create: `services/voice/resona_voice/orchestrator.py`, `services/voice/resona_voice/tools.py`
- Test: `services/voice/tests/test_orchestrator.py`

(`tools.ToolRegistry` is needed by the orchestrator constructor, so it is created here; its tool factories come in Task 5.)

- [ ] **Step 1: Write the failing test**

`services/voice/tests/test_orchestrator.py`:
```python
from resona_voice.fakes import FakeLLM, FakeTTS, ManualClock
from resona_voice.orchestrator import Orchestrator
from resona_voice.tools import ToolRegistry
from resona_voice.types import LLMResponse


async def test_basic_turn_runs_llm_then_streams_tts():
    llm = FakeLLM([LLMResponse(text="Hello there. How can I help?")])
    tts = FakeTTS(chunks_per_clause=2)
    orch = Orchestrator(llm=llm, tts=tts, tools=ToolRegistry(), clock=ManualClock())

    res = await orch.handle_user_turn("hi")

    assert res.text == "Hello there. How can I help?"
    assert res.interrupted is False
    assert res.audio_chunks == 4  # 2 clauses x 2 chunks
    assert tts.synth_calls == ["Hello there.", "How can I help?"]
    stages = {s.stage for s in res.spans}
    assert {"llm", "tts", "turn"} <= stages
```

- [ ] **Step 2: Run test (expect fail)**

Run: `cd services/voice && . .venv/bin/activate && pytest -q tests/test_orchestrator.py`
Expected: FAIL — `resona_voice.orchestrator` / `tools` missing.

- [ ] **Step 3: Implement `tools.py` (registry only)**

```python
from __future__ import annotations

from typing import Awaitable, Callable

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
```

- [ ] **Step 4: Implement `orchestrator.py`**

```python
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
```

- [ ] **Step 5: Run test (expect pass)**

Run: `cd services/voice && . .venv/bin/activate && pytest -q tests/test_orchestrator.py`
Expected: 1 passed.

- [ ] **Step 6: Commit**

```bash
git add services/voice/resona_voice/orchestrator.py services/voice/resona_voice/tools.py services/voice/tests/test_orchestrator.py
git commit -m "feat(voice): turn orchestrator with TTS streaming and latency spans"
```

---

## Task 4: Orchestrator — tool loop + barge-in (TDD)

**Files:**
- Modify: `services/voice/tests/test_orchestrator.py` (append tests)

- [ ] **Step 1: Append the failing tests**

Append to `services/voice/tests/test_orchestrator.py`:
```python
import asyncio

from resona_voice.fakes import BargeInFakeTTS
from resona_voice.types import ToolCall


async def test_tool_call_loop_then_final_text():
    calls: list[dict] = []

    async def fake_book(**kwargs) -> str:
        calls.append(kwargs)
        return "booked 2026-06-10 10:00"

    reg = ToolRegistry()
    reg.register("book_appointment", fake_book, {"name": "book_appointment"})

    llm = FakeLLM(
        [
            LLMResponse(
                tool_calls=[
                    ToolCall(name="book_appointment", arguments={"date": "2026-06-10", "time": "10:00"})
                ]
            ),
            LLMResponse(text="You're all set."),
        ]
    )
    orch = Orchestrator(llm=llm, tts=FakeTTS(), tools=reg, clock=ManualClock())

    res = await orch.handle_user_turn("book me at 10")

    assert res.text == "You're all set."
    assert calls == [{"date": "2026-06-10", "time": "10:00"}]
    assert any(s.stage == "tool" for s in res.spans)


async def test_barge_in_stops_speech_mid_utterance():
    event = asyncio.Event()
    tts = BargeInFakeTTS(event=event, fire_after_chunks=1, chunks_per_clause=2)
    llm = FakeLLM([LLMResponse(text="one. two. three.")])
    orch = Orchestrator(
        llm=llm, tts=tts, tools=ToolRegistry(), clock=ManualClock(), barge_in=event
    )

    res = await orch.handle_user_turn("hi")

    assert res.interrupted is True
    assert res.audio_chunks == 1  # cancelled after the first chunk of the first clause
```

- [ ] **Step 2: Run tests (expect pass — orchestrator already supports both)**

Run: `cd services/voice && . .venv/bin/activate && pytest -q tests/test_orchestrator.py`
Expected: 3 passed. (These tests assert behavior the Task 3 orchestrator already implements; they lock it in. If `test_tool_call_loop` or `test_barge_in` fails, fix `orchestrator.py` until green.)

- [ ] **Step 3: Commit**

```bash
git add services/voice/tests/test_orchestrator.py
git commit -m "test(voice): cover tool-call loop and barge-in interruption"
```

---

## Task 5: Tools — book_appointment + search_knowledge_base (TDD)

**Files:**
- Modify: `services/voice/resona_voice/tools.py` (add factories)
- Test: `services/voice/tests/test_tools.py`

- [ ] **Step 1: Write the failing test**

`services/voice/tests/test_tools.py`:
```python
from resona_voice.tools import make_book_appointment, make_search_knowledge_base


async def test_book_appointment_formats_confirmation():
    class FakeCalendar:
        async def book(self, **kwargs) -> str:
            return f"{kwargs['date']} {kwargs['time']}"

    fn = make_book_appointment(FakeCalendar())
    out = await fn(date="2026-06-10", time="10:00", name="Ana")
    assert "2026-06-10 10:00" in out


async def test_search_knowledge_base_embeds_then_matches():
    class FakeEmbedder:
        async def embed(self, text: str) -> list[float]:
            return [1.0, 0.0]

    class FakeSearch:
        def __init__(self) -> None:
            self.seen: list[tuple[list[float], str]] = []

        async def match(self, embedding: list[float], kb_id: str) -> list[dict]:
            self.seen.append((embedding, kb_id))
            return [{"content": "about pricing"}, {"content": "about refunds"}]

    search = FakeSearch()
    fn = make_search_knowledge_base(FakeEmbedder(), search, kb_id="kb-1")
    out = await fn(query="how much?")

    assert "about pricing" in out
    assert "about refunds" in out
    assert search.seen == [([1.0, 0.0], "kb-1")]
```

- [ ] **Step 2: Run test (expect fail)**

Run: `cd services/voice && . .venv/bin/activate && pytest -q tests/test_tools.py`
Expected: FAIL — `make_book_appointment` / `make_search_knowledge_base` missing.

- [ ] **Step 3: Add factories to `tools.py`**

Append to `services/voice/resona_voice/tools.py`:
```python
from .protocols import Calendar, Embedder, KnowledgeSearch


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
```

- [ ] **Step 4: Run test (expect pass)**

Run: `cd services/voice && . .venv/bin/activate && pytest -q tests/test_tools.py`
Expected: 2 passed.

- [ ] **Step 5: Commit**

```bash
git add services/voice/resona_voice/tools.py services/voice/tests/test_tools.py
git commit -m "feat(voice): book_appointment and search_knowledge_base tools"
```

---

## Task 6: Twilio control plane — TwiML media stream (TDD)

**Files:**
- Create: `services/voice/resona_voice/twiml.py`
- Modify: `services/voice/resona_voice/app.py`
- Modify: `services/voice/tests/test_app.py`

- [ ] **Step 1: Append the failing test**

Append to `services/voice/tests/test_app.py`:
```python
def test_twilio_voice_returns_connect_stream_twiml():
    r = client.post(
        "/twilio/voice",
        data={"CallSid": "CA123", "From": "+15551112222", "To": "+15555550100"},
    )
    assert r.status_code == 200
    assert "application/xml" in r.headers["content-type"]
    body = r.text
    assert "<Response>" in body
    assert "<Connect>" in body
    assert "<Stream" in body
```

- [ ] **Step 2: Run test (expect fail)**

Run: `cd services/voice && . .venv/bin/activate && pytest -q tests/test_app.py`
Expected: FAIL — `/twilio/voice` returns 404 (route not defined).

- [ ] **Step 3: Implement `twiml.py`**

`services/voice/resona_voice/twiml.py`:
```python
from xml.sax.saxutils import quoteattr


def connect_stream_twiml(ws_url: str) -> str:
    """TwiML that bridges the call's audio to our media-stream WebSocket."""
    return (
        '<?xml version="1.0" encoding="UTF-8"?>'
        "<Response>"
        "<Connect>"
        f"<Stream url={quoteattr(ws_url)} />"
        "</Connect>"
        "</Response>"
    )
```

- [ ] **Step 4: Add the route to `app.py`**

Replace `services/voice/resona_voice/app.py` with:
```python
from fastapi import FastAPI, Request, Response

from .config import settings
from .twiml import connect_stream_twiml

app = FastAPI(title="Resona Voice")


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/twilio/voice")
async def twilio_voice(request: Request) -> Response:
    # Twilio posts CallSid/From/To as form data on an inbound call. We respond
    # with TwiML that opens a media stream back to our WebSocket (Plan 2b wires
    # that socket into the Orchestrator).
    await request.form()
    xml = connect_stream_twiml(settings.media_stream_url)
    return Response(content=xml, media_type="application/xml")
```

- [ ] **Step 5: Run tests (expect pass)**

Run: `cd services/voice && . .venv/bin/activate && pytest -q tests/test_app.py`
Expected: 2 passed.

- [ ] **Step 6: Commit**

```bash
git add services/voice/resona_voice/twiml.py services/voice/resona_voice/app.py services/voice/tests/test_app.py
git commit -m "feat(voice): Twilio voice webhook returns media-stream TwiML"
```

---

## Task 7: Full suite green + service README

**Files:**
- Create: `services/voice/README.md`

- [ ] **Step 1: Run the whole suite**

Run: `cd services/voice && . .venv/bin/activate && pytest -q`
Expected: all tests pass (test_app: 2, test_orchestrator: 3, test_tools: 2 = 7 passed).

- [ ] **Step 2: Write `services/voice/README.md`**

```markdown
# Resona Voice

Provider-agnostic real-time voice-agent core: a turn orchestrator (LLM + tool loop,
TTS streaming, barge-in, latency spans) and a Twilio control plane.

## Why protocols + fakes

`Orchestrator` depends only on `protocols.py` interfaces. Tests use deterministic
fakes (no API keys, no audio deps). Plan 2b adds real adapters that implement the
same protocols — Deepgram (STT), Anthropic Claude Haiku (LLM), Cartesia (TTS) — and
a Twilio Media Stream WebSocket that drives `handle_user_turn`.

## Dev

    cd services/voice
    python3 -m venv .venv && . .venv/bin/activate
    pip install -e ".[dev]"
    pytest -q

## Run the control plane

    uvicorn resona_voice.app:app --reload --port 8080
    # POST /twilio/voice returns <Connect><Stream> TwiML; GET /health -> {"status":"ok"}

## Latency budget

Each turn records `LatencySpan`s for `llm`, `tool`, `tts`, and total `turn`. Plan 2b
exports these to Langfuse and the `call_events` table (type `latency_span`) to track
p50/p95 voice-to-voice against the sub-second target.
```

- [ ] **Step 3: Commit**

```bash
git add services/voice/README.md
git commit -m "docs(voice): service overview and dev instructions"
```

---

## Self-Review

**Spec coverage** (design doc §3 real-time pipeline / §4 latency):
- Cascaded turn loop (LLM → TTS), provider-agnostic → Task 3 ✓
- Tool calling (function calling) → Tasks 3–5 ✓
- Barge-in / interruption → Task 4 ✓
- Per-stage latency spans (the measured budget) → Task 3 ✓
- RAG `search_knowledge_base` (mirrors the pgvector `match_knowledge_chunks` RPC: embed → match) → Task 5 ✓
- Twilio Media Stream ingress (TwiML `<Connect><Stream>`) → Task 6 ✓
- **Deferred to Plan 2b (needs keys):** Deepgram/Anthropic/Cartesia adapters, the media-stream WebSocket + audio framing/VAD/endpointing, Supabase Realtime transcript fan-out + `call`/`transcript`/`call_events` persistence, backchannel audio.

**Placeholder scan:** no TBD/TODO; every step has complete code. The only env variability is provider keys (empty by default; unused until 2b).

**Type consistency:** `Orchestrator(llm, tts, tools, clock, ...)` constructor matches all call sites. `LLMResponse(text=..., tool_calls=[...])`, `ToolCall(name=, arguments=)`, `LatencySpan(stage, ms)`, `TurnResult(text, spans, interrupted, audio_chunks)` used identically across orchestrator and tests. `ToolFn` (async, returns `str`) matches `dispatch`, both tool factories, and the fakes. `make_search_knowledge_base(embedder, search, kb_id)` signature matches its test.

**Open risk:** Python 3.14 is very new — if a `pip install` wheel is missing for 3.14, create the venv with 3.12/3.13 (`python3.12 -m venv .venv`) via pyenv/uv. The dependency set is deliberately tiny (FastAPI + pytest + httpx) to minimize this risk.
