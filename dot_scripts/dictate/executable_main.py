import argparse
import subprocess
import sys
import tempfile
import termios
import tty
from pathlib import Path

import numpy as np
import sounddevice as sd
import soundfile as sf
from faster_whisper import WhisperModel


RED = "\033[31m"
ORANGE = "\033[38;5;208m"
RESET = "\033[0m"
CLEAR_LINE = "\033[2K"
CURSOR_START = "\r"


def set_status(message: str, color: str | None = None) -> None:
    if color:
        message = f"{color}{message}{RESET}"

    print(f"{CURSOR_START}{CLEAR_LINE}{message}",
          end="", file=sys.stderr, flush=True)


def wait_for_enter() -> None:
    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)

    try:
        tty.setcbreak(fd)

        while True:
            char = sys.stdin.read(1)

            if char in ("\n", "\r"):
                return
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)


def record_loop(path: Path, sample_rate: int) -> None:
    set_status("Recording... Press Enter to stop.", color=RED)

    chunks = []

    def callback(indata, _frames, _time, status):
        if status:
            print(status, file=sys.stderr)
        chunks.append(indata.copy())

    with sd.InputStream(
        samplerate=sample_rate,
        channels=1,
        dtype="float32",
        callback=callback,
    ):
        wait_for_enter()

    if chunks:
        audio = np.concatenate(chunks, axis=0)
    else:
        audio = np.zeros((0, 1), dtype=np.float32)

    sf.write(path, audio, sample_rate)


def copy_to_clipboard(text: str) -> None:
    subprocess.run(
        ["wl-copy"],
        input=text,
        text=True,
        check=True,
    )


def transcribe(audio_path: Path, args: argparse.Namespace) -> str:
    model = WhisperModel(
        args.model,
        device=args.device,
        compute_type=args.compute_type,
    )

    segments, _info = model.transcribe(
        str(audio_path),
        language=args.language,
        beam_size=args.beam_size,
        vad_filter=True,
    )

    return " ".join(segment.text.strip() for segment in segments).strip()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Record microphone audio and transcribe it locally with faster-whisper."
    )

    parser.add_argument("--model", default="large-v3-turbo")
    parser.add_argument("--language")
    parser.add_argument("--device", default="cuda")
    parser.add_argument("--compute-type", default="float16")
    parser.add_argument("--beam-size", type=int, default=5)
    parser.add_argument("--sample-rate", type=int, default=16000)
    parser.add_argument("--no-copy", action="store_true")
    parser.add_argument("--audio-device")

    args = parser.parse_args()

    if args.language == "auto":
        args.language = None

    return args


def main() -> None:
    args = parse_args()

    if args.audio_device:
        try:
            sd.default.device = int(args.audio_device)
        except ValueError:
            sd.default.device = args.audio_device

    with tempfile.TemporaryDirectory() as tmpdir:
        audio_path = Path(tmpdir) / "dictation.wav"

        record_loop(audio_path, args.sample_rate)

        set_status("Transcribing...", color=ORANGE)
        text = transcribe(audio_path, args)

    set_status(f"\n{text}\n")
    print(file=sys.stderr)

    if not args.no_copy and text:
        copy_to_clipboard(text)


if __name__ == "__main__":
    main()
