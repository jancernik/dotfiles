import base64
import json
import os
import sys
import unicodedata
import urllib.request

DEFAULT_HOST = "https://ollama.cuasar.cc"
DEFAULT_MODEL = "huihui_ai/gemma-4-abliterated:e4b"
DEFAULT_KEEP_ALIVE = -1
SYSTEM_PROMPT = (
    "You format speech transcripts. Add punctuation, capitalization, "
    "and paragraph breaks where appropriate. Do NOT add, remove, replace, "
    "or reorder any words. Do NOT omit any sentence. Do NOT correct grammar "
    "or rephrase. Return only the formatted transcript, nothing else."
)


def words(text: str) -> list[str]:
    result = []
    current = []
    for char in unicodedata.normalize("NFC", text.lower()):
        if char.isalnum() or unicodedata.category(char).startswith("M"):
            current.append(char)
        elif char in "'’" and current:
            continue
        elif current:
            result.append("".join(current))
            current = []
    if current:
        result.append("".join(current))
    return result


def is_word_preserving(raw: str, formatted: str) -> bool:
    return bool(words(raw)) and words(raw) == words(formatted)


def settings() -> tuple[str, str, str | None]:
    host = os.environ.get("DICTATE_OLLAMA_HOST", DEFAULT_HOST).rstrip("/")
    model = os.environ.get("DICTATE_OLLAMA_MODEL", DEFAULT_MODEL)
    user = os.environ.get("DICTATE_OLLAMA_USER")
    password = os.environ.get("DICTATE_OLLAMA_PASSWORD")
    auth = None
    if user and password:
        auth = base64.b64encode(f"{user}:{password}".encode()).decode()
    return host, model, auth


def keep_alive() -> str | int:
    return os.environ.get("DICTATE_OLLAMA_KEEP_ALIVE", DEFAULT_KEEP_ALIVE)


def model_loaded(host: str, model: str, auth: str, timeout: float = 5) -> bool:
    request = urllib.request.Request(
        f"{host}/api/ps", headers={"Authorization": f"Basic {auth}"}
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        status = json.load(response)
    if not isinstance(status, dict) or not isinstance(status.get("models"), list):
        raise TypeError("invalid model status response")
    return any(
        isinstance(entry, dict) and entry.get("name") == model
        for entry in status["models"]
    )


def format_request(
    raw: str, host: str, model: str, auth: str, keep_alive_value: str | None = None
) -> str:
    word_count = len(raw.split())
    payload = json.dumps(
        {
            "model": model,
            "system": SYSTEM_PROMPT,
            "prompt": raw,
            "stream": False,
            "think": False,
            "keep_alive": keep_alive_value or keep_alive(),
            "options": {
                "num_predict": min(2048, max(512, int(word_count * 2.5) + 256)),
                "temperature": 0,
            },
        }
    ).encode()
    request = urllib.request.Request(
        f"{host}/api/generate",
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Basic {auth}",
        },
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        result = json.load(response)
    if not isinstance(result, dict) or not isinstance(result.get("response"), str):
        raise TypeError("invalid formatter response")
    text = result["response"].strip()
    if not text:
        raise ValueError("formatter returned no text")
    return text


def format_transcript(raw: str) -> str:
    host, model, auth = settings()
    if auth is None:
        raise ValueError("formatting credentials are not configured")
    return format_request(raw, host, model, auth)


def maybe_format(raw: str, *, on_status=None) -> str:
    if not raw or not raw.strip():
        return raw
    host, model, auth = settings()
    if auth is None:
        print(
            "\nFormatting skipped: set DICTATE_OLLAMA_USER and DICTATE_OLLAMA_PASSWORD",
            file=sys.stderr,
        )
        return raw
    try:
        loaded = model_loaded(host, model, auth)
    except (OSError, TypeError, ValueError):
        loaded = None
    try:
        if loaded is False:
            if on_status is not None:
                on_status("Loading formatting model…")
            else:
                print("\nLoading formatting model…", file=sys.stderr)
        formatted = format_request(raw, host, model, auth)
    except (OSError, TypeError, ValueError) as error:
        print(
            f"\nFormatting unavailable, using raw transcript: {error}",
            file=sys.stderr,
        )
        return raw
    if not is_word_preserving(raw, formatted):
        print(
            "\nFormatting changed words, using raw transcript",
            file=sys.stderr,
        )
        return raw
    return formatted
