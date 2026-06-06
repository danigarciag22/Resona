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
