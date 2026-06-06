from fastapi import FastAPI, Response

from .config import settings
from .twiml import connect_stream_twiml

app = FastAPI(title="Resona Voice")


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/twilio/voice")
async def twilio_voice() -> Response:
    # Twilio POSTs CallSid/From/To (form-encoded) on an inbound call. This slice
    # ignores the body and always returns TwiML that opens a media stream back to
    # our WebSocket. Plan 2b parses the form (needs python-multipart) to look up
    # the dialed number and route to the right agent.
    xml = connect_stream_twiml(settings.media_stream_url)
    return Response(content=xml, media_type="application/xml")
