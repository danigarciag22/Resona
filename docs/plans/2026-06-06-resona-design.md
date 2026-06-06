# Resona — Architecture & Latency Design

**Date:** 2026-06-06
**Status:** Design locked (pre-implementation)
**Author:** Architecture brainstorm session

> Resona is a B2B platform that does two things on one engine: (a) **real-time AI voice agents** that work inbound/outbound calls — lead qualification, scheduling, L1 support — with natural, sub-second voice, tool use (CRM, calendar, ticketing) and RAG over a knowledge base; and (b) **conversation intelligence** that turns every call (AI or human) into structured insight — diarized transcript, sentiment, topics, objections, summary, action items, compliance flags, and CRM sync.

The central engineering thesis: **sub-second, human-feeling voice latency**. This document defines the latency budget explicitly and the architecture that hits it.

---

## 1. Locked decisions

| Layer | Choice | Why this one |
|---|---|---|
| Voice pipeline | **Cascaded** (VAD → STT → LLM → TTS), streamed & overlapped | Per-stage latency budget is measurable and optimizable; clean tool-use + RAG; async diarization reuses the same ASR |
| Telephony + transport | **Twilio Media Streams** (WebSocket, 8 kHz µ-law) | Real PSTN, free trial numbers, demoable; first-class Pipecat support |
| Orchestration | **Pipecat** (Python) | Purpose-built for this exact cascaded pipeline; barge-in, interruption, endpointing out of the box |
| Streaming STT | **Deepgram Nova** (phonecall model) | Streaming partials, low latency, built-in redaction + diarization for the async path |
| In-call LLM | **Claude Haiku 4.5** | Fast TTFT (~400 ms), strong function-calling + instruction-following, one vendor for in-call + async |
| Async analysis LLM | **Claude Sonnet 4.6** | Deep reasoning for summary/objections/compliance; latency irrelevant in batch |
| Streaming TTS | **Cartesia Sonic** | ~90 ms first audio, sentence-level streaming, natural voices |
| Embeddings | **Voyage `voyage-3-lite`** | Strong retrieval quality, Anthropic-aligned; cheap |
| Vector + search | **pgvector + Postgres FTS** | Hybrid semantic + keyword in one store; RLS applies; no extra service |
| DB / Auth / Storage / Realtime | **Supabase** | Postgres + RLS + Auth + object storage (recordings) + Realtime (live transcript) in one platform |
| Queue / broker / pub-sub | **Redis + Arq** | Async job queue + internal pub/sub; lightweight Python-async worker |
| Web | **Next.js (App Router) + TS + Tailwind + shadcn/ui + WaveSurfer.js** on **Vercel** | RSC for data-heavy views; Supabase Realtime for live views |
| Voice compute | **Fly.io region `iad`** — always-warm | Low-latency persistent WebSockets, regional pinning, **never serverless** |
| Async compute | **Fly Machines** — scale-to-zero | Cheap batch; same platform as voice |
| Observability | **Langfuse + Sentry** | LLM/turn tracing + per-stage latency spans + error tracking |

**Deliberate constraint: no GPU anywhere.** All ML is via API (Deepgram, Anthropic, Cartesia, Voyage). This trades some model control and per-minute cost for radically simpler ops — the correct call for a solo build. Self-hosting (Whisper / pyannote / Kokoro / Orpheus on GPU) is documented as a later cost/control optimization in §11.

---

## 2. System overview

```
═══════════════════════════ REAL-TIME (voice agent) ═══════════════════════════

  caller ──PSTN──► Twilio ──Media Stream (WS, 8kHz µ-law)──► Voice Service (Fly iad)
                     ▲                                          │
                     │                                          ▼
                     │                            ┌─────────────────────────────┐
                     │                            │  Pipecat orchestrator        │
                     │                            │   VAD / smart endpointing    │
                     │                            │   Deepgram STT (stream)      │
                     │                            │   Claude Haiku (tools + RAG) │
                     │                            │   Cartesia TTS (stream)      │
                     │                            │   barge-in · backchannel     │
                     └────── agent audio ─────────┤                              │
                                                  └──────────────┬───────────────┘
                                                  partial/final  │  per-turn
                                                  transcript     │  latency spans
                                                                 ▼
                              Supabase Realtime channel  ──►  LiveCallMonitor (browser)
                              (live words · sentiment · waveform)

  on hangup: recording uploaded to Supabase Storage ──► enqueue async job (Redis)

═══════════════════════════ ASYNC (conversation intelligence) ═════════════════

  recording ─► Redis queue ─► Arq worker (Fly machine, scale-to-zero)
        │
        ├─► Deepgram pre-recorded: diarized ASR  ──► transcripts (segments + speakers)
        ├─► Claude Sonnet: sentiment · topics · objections · summary · action items
        │                  · compliance flags · scorecard                ──► analyses
        ├─► Voyage embeddings (call-level + chunk-level) ──► pgvector
        └─► CRM / calendar sync (integrations) ──► webhook ──► Postgres update

                              all rows ──► Next.js (RSC) dashboards
```

Two hard-separated planes: **real-time (latency-optimized, always-warm)** vs **async (cost-optimized, scale-to-zero)**. They share only Postgres, Storage, and Redis.

---

## 3. Latency budget — the centerpiece

**Metric:** *voice-to-voice* latency = time from the moment the caller stops speaking to the moment the caller hears the agent's first audio. Target **p50 ≤ 1.0 s (stretch 800 ms)**; mask residual with backchannel.

Stages overlap (STT runs during speech; TTS starts on the LLM's first clause, not its last token), so the effective total is **less than the naive sum**.

| Stage | p50 | p95 | Dominant lever |
|---|---:|---:|---|
| End-of-turn detection (silence + semantic) | 250 ms | 450 ms | Pipecat smart-turn + Silero VAD; threshold tuning — **biggest UX dial** |
| STT finalization (post-endpoint; rest streamed live) | 60 ms | 130 ms | Deepgram phonecall model; mostly overlapped during speech |
| Voice-service processing + transport to LLM | 40 ms | 90 ms | In-region; persistent warm connections |
| LLM **time-to-first-clause** (Claude Haiku) | 420 ms | 720 ms | Stream into TTS on first clause; speculative early trigger on confident endpoint |
| TTS first audio (Cartesia Sonic) | 90 ms | 180 ms | Streaming; sentence chunking |
| Return transport + jitter/playout buffer | 110 ms | 200 ms | Twilio leg + minimal buffer |
| **Effective voice-to-voice** | **~870 ms** | **~1.5 s** | sub-1 s p50; p95 masked by backchannel |

**Honest read:** p50 sits right at the sub-second boundary for a Twilio + cascaded stack; claiming sub-500 ms here would be dishonest. The two levers that move the needle most are **endpointing** and **LLM TTFT**. p95 is where it gets hard — which is exactly why the UX masks it.

### Latency techniques (the engineering that earns the premium)

1. **Pipeline overlap / streaming** — STT emits partials during speech; the LLM streams; TTS synthesizes the first clause while the LLM is still generating. First audio out depends on time-to-first-*clause*, not full completion.
2. **Smart endpointing** — semantic turn detection (Pipecat smart-turn) + VAD instead of a fixed silence timer; cuts the single largest delay without cutting the caller off.
3. **Speculative LLM trigger** — on a high-confidence endpoint, fire the LLM before the silence timer fully elapses; discard if the caller resumes.
4. **Backchannel + filler** — short acknowledgements ("mm-hm", "let me check that…") emitted while the LLM thinks. This is the key UX trick that makes p95 *feel* instant and the agent feel human.
5. **Warm everything** — persistent WebSockets to Deepgram/Cartesia; always-warm Fly compute (no cold starts, ever); connection pooling; prewarmed sessions.
6. **Regional co-location** — Twilio us1 (Ashburn) ↔ Fly `iad` (Ashburn) ↔ Deepgram/Cartesia/Anthropic US-East ↔ Supabase us-east-1. Every hop stays in one metro. Each saved RTT is real.
7. **Barge-in** — inbound VAD during agent speech immediately cancels TTS playout *and* aborts the in-flight LLM/TTS, so the agent goes quiet the instant the caller talks over it.

### SLOs

Per-turn spans (endpoint, STT, LLM-first-clause, TTS-first-byte, transport) emitted to Langfuse and a `/metrics` endpoint. Track **p50 / p95 / p99 voice-to-voice** per agent. Alert when p95 > 1.5 s sustained.

---

## 4. Real-time voice service (Fly `iad`, always-warm)

**Control plane:** FastAPI.
- `POST /twilio/voice` — Twilio webhook on inbound call. Returns TwiML `<Connect><Stream>` pointing at the service's WSS endpoint, keyed to the dialed number → agent.
- `WSS /media/{call_id}` — Twilio Media Stream. Frames pumped into the Pipecat pipeline.
- Outbound: `POST /calls/outbound` triggers a Twilio call that connects back to the same stream endpoint.

**Pipeline (Pipecat):** `TwilioFrameSerializer → SileroVAD + smart-turn → DeepgramSTT → context aggregator → AnthropicLLM (Haiku, tools + RAG) → CartesiaTTS → TwilioFrameSerializer`.

**Tools (function-calling):** `book_appointment` (Cal.com), `lookup_crm`, `create_ticket`, `transfer_to_human`, `search_knowledge_base`. Each tool is an async function; results stream back into the LLM context. The agent's `tools` jsonb defines which are enabled.

**RAG:** `search_knowledge_base(query)` embeds the query (Voyage) and does a pgvector similarity search over `knowledge_chunks` scoped to the agent's KB, returning top-k passages injected as tool output. Pre-warm: the agent's most-likely passages can be prefetched at call start.

**Guardrails:** `guardrails` jsonb — prohibited topics, max call duration, mandatory disclosures (e.g. recording consent, compliance script lines), escalation triggers. Enforced as system-prompt constraints + runtime checks.

**Live fan-out:** each partial/final transcript segment + rolling sentiment is published to Supabase Realtime channel `call:{call_id}`. The browser subscribes via `supabase-js` — no custom WS gateway needed (resolves Vercel's serverless WS limitation). Internal Redis pub/sub coordinates multi-worker state and doubles as the Arq broker. *Fallback if Realtime throughput is exceeded under many concurrent calls:* a dedicated Node/Python WS gateway behind the same Redis pub/sub.

**On hangup:** finalize the call row, upload the recording to Supabase Storage, enqueue the async analysis job in Redis.

---

## 5. Async conversation-intelligence pipeline (Fly Machines, scale-to-zero)

Arq worker consumes from Redis. Per recording:

1. **Diarized ASR** — Deepgram pre-recorded API with `diarize=true` → speaker-labelled segments with word timestamps. *(Upgrade path: pyannote.audio for SOTA diarization if a GPU is added.)*
2. **Analysis (Claude Sonnet 4.6)** — one structured-output call (or a small chain) producing: overall + timeline sentiment, topics, detected objections, summary, action items, and a coaching scorecard. Compliance is a second pass over rule definitions → `compliance_flags` with severity + excerpt + timestamp.
3. **Embeddings (Voyage)** — call-level embedding for "find similar calls", plus chunk-level for passage search → pgvector.
4. **CRM / calendar sync** — push summary, disposition, and action items to the connected CRM via `integrations`; emit an `audit_log` entry.

PII/PCI redaction (Deepgram redaction) runs for regulated verticals (collections, clinics) before storage.

---

## 6. Data model (Postgres + RLS + pgvector)

```sql
-- Tenancy
organizations(id, name, created_at)
profiles(id → auth.users, full_name, avatar_url)          -- Supabase Auth
memberships(org_id, user_id, role)                        -- RLS anchor

-- Voice config
phone_numbers(id, org_id, provider, e164, agent_id, capabilities jsonb)
knowledge_bases(id, org_id, name)
knowledge_documents(id, kb_id, org_id, source_uri, title, status)
knowledge_chunks(id, document_id, org_id, content text,
                 embedding vector(1024), token_count)     -- pgvector
agents(id, org_id, name, voice_id, persona_prompt, llm_model,
       tools jsonb, knowledge_base_id, guardrails jsonb, created_at)

-- Calls
calls(id, org_id, agent_id, phone_number_id, direction, from_e164, to_e164,
      status, handled_by, disposition, recording_uri,
      started_at, ended_at, duration_ms)
call_events(id, call_id, org_id, ts, type, payload jsonb)  -- tool calls,
            -- barge-ins, transfers, per-turn latency spans
transcripts(id, call_id, org_id, segments jsonb,           -- speaker+ts+text
            fts tsvector GENERATED)                         -- keyword search

-- Intelligence
analyses(id, call_id, org_id, sentiment, sentiment_timeline jsonb,
         topics jsonb, summary, action_items jsonb, objections jsonb,
         model, created_at)
call_embeddings(id, call_id, org_id, embedding vector(1024))  -- semantic search
compliance_flags(id, call_id, org_id, rule, severity, excerpt, ts_ms, resolved)
scorecards(id, call_id, org_id, rep_id, scores jsonb, coaching_notes, model)

-- Integrations & audit
integrations(id, org_id, provider, status, token_ref)      -- token in secrets mgr
audit_log(id, org_id, actor, action, target, ts, metadata jsonb)
```

**RLS:** every org-scoped table carries `org_id`. Policy:
`org_id IN (SELECT org_id FROM memberships WHERE user_id = auth.uid())`.
The voice/async services use the Supabase **service role** (RLS bypass) and enforce org scoping in application logic. `token_ref` stores a pointer to a secrets manager, never a raw OAuth token.

**Search:** hybrid — pgvector cosine over `call_embeddings`/`knowledge_chunks` **+** Postgres FTS over `transcripts.fts`, fused (reciprocal-rank). One database, RLS-safe, no OpenSearch/Meilisearch to run.

---

## 7. Web app (Next.js App Router on Vercel)

**Rendering strategy — matched to data shape:**

| Surface | Strategy | Reason |
|---|---|---|
| Marketing | SSG / ISR | Static, cacheable |
| CallLibrary, analytics, scorecards, compliance dashboard | SSR (RSC) | Precomputed data → fast first paint, no client fetch waterfall |
| **LiveCallMonitor**, AgentBuilder | CSR + Supabase Realtime | Interactivity and real-time *are* the product |

**Key components:**
- **LiveCallMonitor** ⭐ — streaming transcript (words appear as spoken), live waveform, color-shifting sentiment, tool-call timeline. Subscribes to `call:{id}`.
- **AgentBuilder** — persona, voice, tools, knowledge base, guardrails. Persists via Server Actions.
- **CallLibrary** — semantically searchable call list; skeletons; optimistic tagging.
- **CallPlayer** — WaveSurfer audio synced to transcript + insight timeline; click-to-seek.
- **Command center** — call volume, % AI-vs-human, average handle time, sentiment trends, top objections/topics, conversion correlation, compliance flags.

**Client ↔ server:** Server Actions for agent config; Supabase Realtime for live transcript; Redis queue + webhook for post-call analysis; SSE for streaming async summaries.

---

## 8. Deployment & regional co-location

| Workload | Platform | Region | Mode |
|---|---|---|---|
| Web | Vercel | global edge + functions us-east-1 | serverless OK |
| **Voice service** | **Fly.io** | **`iad` (Ashburn)** | **always-warm, never serverless** |
| Async workers | Fly Machines | `iad` | scale-to-zero |
| Postgres / Auth / Storage / Realtime | Supabase | us-east-1 | managed |
| Redis | Upstash or Fly Redis | us-east-1 / `iad` | managed/co-located |
| Telephony | Twilio | us1 (Ashburn) | — |
| STT / LLM / TTS / embeddings | Deepgram · Anthropic · Cartesia · Voyage | US-East endpoints | API |

**Everything in the Ashburn / us-east-1 metro.** The hard separation — latency-optimized always-warm voice vs cost-optimized scale-to-zero analytics — is the infrastructure story that demonstrates real engineering. Cold-start-prone serverless is explicitly banned from the voice path.

---

## 9. Observability

- **Langfuse** — per-turn traces with the latency spans from §3; LLM input/output, tool calls, RAG retrievals. The latency SLO dashboard reads from here.
- **Sentry** — errors across web, voice, and workers.
- **`/metrics`** — Prometheus-style p50/p95/p99 voice-to-voice per agent. *(Grafana later if self-hosting.)*

---

## 10. Security, multi-tenancy & compliance

- **Isolation:** Postgres RLS on `org_id` for every tenant table; Supabase Auth for users; service-role access confined to backend workers.
- **Secrets:** provider keys and per-org OAuth tokens in a secrets manager; DB stores only `token_ref`.
- **Recording consent:** mandatory disclosure prompt at call start (configurable per guardrails) to satisfy two-party-consent jurisdictions.
- **Redaction:** Deepgram PII/PCI redaction for regulated verticals before persistence.
- **Audit:** `audit_log` for config changes, integration syncs, and data access.

---

## 11. Build-vs-buy summary

| Capability | Choice | Type | Alt / upgrade |
|---|---|---|---|
| Telephony | Twilio | Buy | Telnyx (cheaper), LiveKit (wideband WebRTC) |
| Orchestration | Pipecat | OSS self-run | LiveKit Agents |
| STT | Deepgram | API | AssemblyAI; self-host Whisper (GPU) |
| In-call LLM | Claude Haiku 4.5 | API | Groq Llama (lower TTFT) |
| Analysis LLM | Claude Sonnet 4.6 | API | GPT-4o |
| TTS | Cartesia Sonic | API | ElevenLabs Flash; self-host Kokoro/Orpheus (GPU) |
| Embeddings | Voyage | API | OpenAI text-embedding-3-small |
| Vector + search | pgvector + FTS | OSS in-DB | OpenSearch / Meilisearch |
| Diarization | Deepgram | API | pyannote.audio (GPU, SOTA) |
| DB/Auth/Storage/Realtime | Supabase | Managed | Neon + Clerk + Vercel Blob |
| Queue | Redis + Arq | OSS | Vercel Queues |
| Voice compute | Fly.io always-warm | — | Railway / Render / AWS ECS |
| Async compute | Fly Machines | — | Modal |

---

## 12. MVP vertical slice (Phase 1 cut line)

**In:**
- One org, Supabase Auth.
- One Twilio number → one agent (persona + RAG knowledge base + one real tool: `book_appointment` via Cal.com).
- Pipecat voice service on Fly `iad`: Deepgram + Haiku + Cartesia, with barge-in and backchannel.
- Live transcript → Supabase Realtime → **LiveCallMonitor** (streaming words + rolling sentiment + waveform).
- On hangup → async worker → Deepgram diarized ASR + Sonnet analysis → `calls` / `transcripts` / `analyses`.
- **CallLibrary** + **CallPlayer** (WaveSurfer, synced transcript).
- Latency instrumentation: per-turn spans → Langfuse + `/metrics` p50/p95.

**Out (deliberately):** outbound campaigns, billing/seats, scorecards/coaching UI, compliance dashboard, CRM sync beyond Cal.com, fine-tuning, multi-agent routing.

**Definition of done:** a real phone call rings, the AI answers, books an appointment using a tool + KB, the live transcript streams to the browser sub-second, and after hangup the call appears in the library with a diarized transcript, summary, and sentiment.

### Roadmap

- **Phase 2 — Intelligence:** command-center analytics, scorecards/coaching, compliance dashboard + rules, semantic call search.
- **Phase 3 — Integrations & scale:** CRM/calendar OAuth integrations, outbound campaigns, multi-tenant billing, dedicated WS gateway if Realtime saturates.
- **Phase 4 — Verticals & cost:** packaged verticals (clinic scheduling, real-estate qualification, collections-with-compliance-script); self-hosted STT/TTS on GPU for per-minute cost reduction; ASR fine-tuning for domain vocabulary.

---

## 13. Risks & open questions

| Risk | Mitigation |
|---|---|
| p95 voice-to-voice > 1 s on hard turns | Backchannel/filler, endpoint tuning, route hard turns to a faster path or pre-generated responses |
| 8 kHz µ-law narrowband hurts STT accuracy | Deepgram phonecall model; consider LiveKit wideband path later |
| Twilio us1 ↔ Fly `iad` actual RTT | Measure real RTT early; pin regions; verify before committing the budget |
| Barge-in false triggers (echo, crosstalk) | Acoustic echo cancellation, VAD threshold tuning, server-side echo suppression |
| Cost per minute (telephony + STT + LLM + TTS) | Rough **$0.05–0.15/min** — validate against live pricing; self-host later to compress |
| Supabase Realtime throughput at many concurrent live calls | Dedicated WS gateway fallback behind the same Redis pub/sub |
| Recording consent across jurisdictions | Mandatory per-guardrail disclosure prompt; configurable by vertical |

---

*Next: set up an isolated worktree and write the Phase-1 implementation plan, or stand up the killer vertical slice directly.*
