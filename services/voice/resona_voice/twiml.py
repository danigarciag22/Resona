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
