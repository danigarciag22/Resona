import asyncio

from resona_voice.fakes import BargeInFakeTTS, FakeLLM, FakeTTS, ManualClock
from resona_voice.orchestrator import Orchestrator
from resona_voice.tools import ToolRegistry
from resona_voice.types import LLMResponse, ToolCall


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
                    ToolCall(
                        name="book_appointment",
                        arguments={"date": "2026-06-10", "time": "10:00"},
                    )
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
