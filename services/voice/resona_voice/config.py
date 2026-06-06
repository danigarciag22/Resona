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
