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
