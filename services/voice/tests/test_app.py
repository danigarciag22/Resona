from fastapi.testclient import TestClient

from resona_voice.app import app

client = TestClient(app)


def test_health_ok():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


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
