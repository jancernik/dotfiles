#!/usr/bin/env python3

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import termios
import tty
from datetime import datetime
from pathlib import Path
from uuid import uuid4

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

    print(f"{CURSOR_START}{CLEAR_LINE}{message}", end="", file=sys.stderr, flush=True)


def wait_for_enter() -> None:
    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)

    try:
        tty.setcbreak(fd)

        while True:
            char = sys.stdin.read(1)

            if char in ("\n", "\r"):
                return
            if char == "\x1b":
                raise KeyboardInterrupt
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)


def record_loop(path: Path, sample_rate: int | None) -> None:
    if sample_rate is None:
        sample_rate = round(sd.query_devices(kind="input")["default_samplerate"])
    set_status(f"Recording at {sample_rate} Hz... Press Enter to stop.", color=RED)

    chunks = []
    capture_statuses = []

    def callback(indata, _frames, _time, status):
        if status:
            capture_statuses.append(status)
        chunks.append(indata.copy())

    with sd.InputStream(
        samplerate=sample_rate,
        channels=1,
        dtype="float32",
        callback=callback,
    ):
        wait_for_enter()

    if capture_statuses:
        warnings = ", ".join(dict.fromkeys(map(str, capture_statuses)))
        print(f"\nAudio capture warning: {warnings}", file=sys.stderr)
    if not chunks:
        raise RuntimeError("No audio was captured")

    audio = np.concatenate(chunks, axis=0)
    sf.write(path, audio, sample_rate, subtype="PCM_24")


def save_audio(source: Path, destination: Path) -> None:
    fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "wb") as output, source.open("rb") as input_file:
            shutil.copyfileobj(input_file, output)
    except BaseException:
        destination.unlink(missing_ok=True)
        raise


def recording_directory() -> Path:
    state_home = Path(
        os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state"
    ).expanduser()
    if not state_home.is_absolute():
        state_home = Path.home() / ".local/state"
    directory = state_home / "dictate" / "recordings"
    if directory.is_symlink():
        raise PermissionError(f"Recording directory is a symlink: {directory}")
    directory.mkdir(parents=True, mode=0o700, exist_ok=True)
    if directory.stat().st_mode & 0o077:
        raise PermissionError(
            f"Recording directory must be private (mode 0700): {directory}"
        )
    return directory


def archived_audio_path(directory: Path) -> Path:
    timestamp = datetime.now().astimezone().strftime("%Y%m%d-%H%M%S-%f")
    return directory / f"dictation-{timestamp}-{uuid4().hex[:8]}.wav"


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
        condition_on_previous_text=False,
    )

    return " ".join(segment.text.strip() for segment in segments).strip()


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Record microphone audio and transcribe it locally with faster-whisper."
    )

    parser.add_argument("--model", default="large-v3", help="Whisper model")
    parser.add_argument(
        "--language", default="en", help="Use 'auto' for language detection"
    )
    parser.add_argument("--device", default="cuda")
    parser.add_argument("--compute-type", default="float16")
    parser.add_argument("--beam-size", type=int, default=5)
    parser.add_argument(
        "--sample-rate",
        type=int,
        help="Recording rate; defaults to the input device's native rate",
    )
    parser.add_argument("--no-copy", action="store_true")
    parser.add_argument("--audio-device")
    parser.add_argument(
        "--audio-file",
        type=Path,
        help="Transcribe a saved recording instead of recording",
    )
    parser.add_argument(
        "--save-audio",
        type=Path,
        help="Keep a private WAV at this new path for local comparison",
    )
    parser.add_argument(
        "--keep-recordings",
        action="store_true",
        help="Archive each new recording in $XDG_STATE_HOME/dictate/recordings (default ~/.local/state/dictate/recordings)",
    )
    args = parser.parse_args(argv)
    if args.sample_rate is not None and args.sample_rate <= 0:
        parser.error("--sample-rate must be positive")
    if args.audio_file and not args.audio_file.is_file():
        parser.error("--audio-file must name an existing file")
    if args.audio_file and (args.save_audio or args.keep_recordings):
        parser.error("saving audio requires a new recording")
    if args.save_audio and args.keep_recordings:
        parser.error("use either --save-audio or --keep-recordings")
    if args.save_audio and not args.save_audio.parent.is_dir():
        parser.error("--save-audio directory does not exist")
    if args.save_audio and args.save_audio.exists():
        parser.error("--save-audio must name a new file")
    if args.language == "auto":
        args.language = None

    return args


def main() -> None:
    args = parse_args()
    archive_directory = recording_directory() if args.keep_recordings else None

    if args.audio_device:
        try:
            sd.default.device = int(args.audio_device)
        except ValueError:
            sd.default.device = args.audio_device

    with tempfile.TemporaryDirectory() as tmpdir:
        audio_path = args.audio_file or Path(tmpdir) / "dictation.wav"
        if not args.audio_file:
            record_loop(audio_path, args.sample_rate)
            destination = args.save_audio
            if archive_directory is not None:
                destination = archived_audio_path(archive_directory)
            if destination is not None:
                save_audio(audio_path, destination)
                print(f"\nSaved recording to {destination}", file=sys.stderr)

        set_status("Transcribing...", color=ORANGE)
        text = transcribe(audio_path, args)

    set_status("")
    print(text)

    if not args.no_copy and text:
        copy_to_clipboard(text)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        set_status("")
        print(file=sys.stderr)
        sys.exit(0)
