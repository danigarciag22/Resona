# Resona

Real-time AI voice agents + conversation intelligence for B2B teams.

Resona puts an AI on the phone — answering inbound/outbound calls with natural,
sub-second voice that can use tools (CRM, calendar, ticketing) and answer from a
knowledge base (RAG) — and turns every call (AI or human) into structured
intelligence: diarized transcript, sentiment, topics, objections, summary,
action items, and compliance flags.

## Status

Architecture & latency design complete. Implementation pending.

📐 **[Architecture & Latency Design →](docs/plans/2026-06-06-resona-design.md)**

## Stack (planned)

- **Web:** Next.js (App Router), TypeScript, Tailwind, shadcn/ui, WaveSurfer.js — on Vercel
- **Voice (real-time):** Python · Pipecat · Twilio Media Streams · Deepgram (STT) · Claude Haiku 4.5 (LLM) · Cartesia (TTS) — on Fly.io, always-warm, co-located with Twilio in us-east
- **Intelligence (async):** Deepgram diarized ASR · Claude Sonnet 4.6 · Voyage embeddings — on Fly Machines, scale-to-zero
- **Data:** Supabase (Postgres + RLS + Auth + Storage + Realtime) · pgvector · Redis

Engineering thesis: **sub-second voice-to-voice latency** (target p50 ≤ 1s), with the latency budget documented and measured per stage.
