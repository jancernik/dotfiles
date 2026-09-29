import fcntl
import json
import os
import socket
import stat
import subprocess
import sys
import tempfile
import time
from collections.abc import Callable
from pathlib import Path

WORKER_PATH = Path(__file__).with_name("main.py")


def runtime_directory() -> Path:
    base = Path(os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir())
    directory = base / f"dictate-{os.getuid()}"
    if directory.is_symlink():
        raise PermissionError(f"Runtime directory is a symlink: {directory}")
    directory.mkdir(mode=0o700, exist_ok=True)
    mode = directory.stat()
    if mode.st_uid != os.getuid() or stat.S_IMODE(mode.st_mode) & 0o077:
        raise PermissionError(f"Runtime directory must be private: {directory}")
    return directory


def lock_file(path: Path):
    fd = os.open(path, os.O_CREAT | os.O_RDONLY | os.O_NOFOLLOW, 0o600)
    return os.fdopen(fd, "rb")


def request_stop(socket_path: Path) -> None:
    deadline = time.monotonic() + 0.5
    while True:
        try:
            with socket.socket(socket.AF_UNIX) as client:
                client.settimeout(0.5)
                client.connect(str(socket_path))
                client.sendall(b"stop")
            return
        except (FileNotFoundError, ConnectionRefusedError):
            if time.monotonic() >= deadline:
                return
            time.sleep(0.02)
        except OSError:
            return


def launch_or_stop(arguments: list[str]) -> None:
    directory = runtime_directory()
    socket_path = directory / "control.sock"
    with lock_file(directory / "control.lock") as control:
        fcntl.flock(control, fcntl.LOCK_EX)
        with lock_file(directory / "session.lock") as session:
            try:
                fcntl.flock(session, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                request_stop(socket_path)
                return
            fcntl.flock(session, fcntl.LOCK_UN)

        socket_path.unlink(missing_ok=True)
        log_path = directory / "session.log"
        log_fd = os.open(
            log_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600
        )
        try:
            worker = subprocess.Popen(
                [sys.executable, str(WORKER_PATH), "--minishell-worker", *arguments],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=log_fd,
                start_new_session=True,
            )
        finally:
            os.close(log_fd)

        deadline = time.monotonic() + 5
        while worker.poll() is None and time.monotonic() < deadline:
            if socket_path.exists():
                return
            time.sleep(0.02)
        if worker.poll() is None:
            worker.terminate()
            try:
                worker.wait(timeout=2)
            except subprocess.TimeoutExpired:
                worker.kill()
                worker.wait()
        raise RuntimeError(f"Dictation could not start; see {log_path}")


def toggle(job: Callable[[Callable[[], None]], None]) -> None:
    directory = runtime_directory()
    socket_path = directory / "control.sock"
    with lock_file(directory / "session.lock") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            request_stop(socket_path)
            return

        socket_path.unlink(missing_ok=True)
        with socket.socket(socket.AF_UNIX) as listener:
            listener.bind(str(socket_path))
            listener.listen(2)

            def wait_for_stop() -> None:
                while True:
                    with listener.accept()[0] as client:
                        if client.recv(16) == b"stop":
                            break
                listener.close()
                socket_path.unlink(missing_ok=True)

            try:
                job(wait_for_stop)
            finally:
                listener.close()
                socket_path.unlink(missing_ok=True)


def focused_monitor() -> str:
    try:
        result = subprocess.run(
            ["hyprctl", "-j", "activeworkspace"],
            capture_output=True,
            text=True,
            timeout=1,
            check=True,
        )
        monitor = json.loads(result.stdout).get("monitor")
        return monitor if isinstance(monitor, str) else ""
    except (
        OSError,
        ValueError,
        subprocess.CalledProcessError,
        subprocess.TimeoutExpired,
    ):
        return ""


class Osd:
    def __init__(self) -> None:
        self.monitor = focused_monitor()

    def call(self, method: str, *args: str) -> bool:
        try:
            result = subprocess.run(
                [
                    "qs",
                    "ipc",
                    "-p",
                    str(Path.home() / "minishell"),
                    "call",
                    "osd",
                    method,
                    *args,
                ],
                capture_output=True,
                text=True,
                timeout=1,
                check=False,
            )
            return result.returncode == 0 and result.stdout.strip() == "true"
        except (OSError, subprocess.TimeoutExpired):
            return False

    def show(self, text: str, icon: str, hold_ms: int = 3000) -> bool:
        payload = {
            "key": "dictate",
            "text": text,
            "icon": icon,
            "hold": True,
            "holdMs": hold_ms,
        }
        if self.monitor:
            payload["monitor"] = self.monitor
        return self.call("request", json.dumps(payload))

    def finish(self, text: str, icon: str) -> None:
        if self.monitor:
            method, args = "unlockOn", ("dictate", self.monitor)
        else:
            method, args = "unlock", ("dictate",)
        if self.show(text, icon):
            self.call(method, *args)
        else:
            dismiss = "dismissOn" if self.monitor else "dismiss"
            self.call(dismiss, *args)
