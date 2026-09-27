#!/usr/bin/env python3
import argparse
import fcntl
import hashlib
import json
import logging
import os
import re
import secrets
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, replace
from logging.handlers import RotatingFileHandler
from pathlib import Path

LOG = logging.getLogger("brightness")


class AlreadyRunning(RuntimeError):
    pass


BACKLIGHT_MIN = 12
DDC_TIMEOUT = 8
DETECT_TIMEOUT = 18
SOCKET_TIMEOUT = 0.6


def runtime_dir():
    base = os.environ.get("XDG_RUNTIME_DIR", "")
    if not base or not Path(base).is_dir():
        raise RuntimeError("XDG_RUNTIME_DIR is required")
    return Path(base) / "minishell"


def state_dir():
    return (
        Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
        / "minishell"
    )


def sys_root():
    return Path(os.environ.get("MINISHELL_BRIGHTNESS_SYS_ROOT", "/sys"))


def json_write(path, data):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=".brightness-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            json.dump(data, output, separators=(",", ":"))
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def command(args, timeout):
    return subprocess.run(
        args, capture_output=True, text=True, timeout=timeout, check=True
    ).stdout


@dataclass(frozen=True)
class Device:
    id: str
    backend: str
    connector: str
    address: str
    label: str
    raw_max: int = 100
    identity: str = ""


def parse_ddc_detection(output):
    devices = []
    bus = connector = label = ""

    def add():
        if not bus or not label:
            return
        name = (
            connector.partition("-")[2]
            if re.fullmatch(r"card\d+-[A-Za-z0-9-]+", connector)
            else ""
        )
        devices.append(
            Device(
                "ddc:" + (connector or "i2c-" + bus),
                "ddcutil",
                name,
                bus,
                label or name or bus,
            )
        )

    for line in output.splitlines() + ["Display end"]:
        if re.match(r"^Display (?:\d+|end)\b", line):
            add()
            bus = connector = label = ""
        elif match := re.search(r"I2C bus:\s*/dev/i2c-(\d+)", line):
            bus = match.group(1)
        elif match := re.search(r"DRM connector:\s*(\S+)", line):
            connector = match.group(1)
        elif match := re.search(r"Monitor:\s*(.*)", line):
            label = match.group(1).strip()
    return devices


def discover():
    devices = []
    ddc_ok = True
    root = sys_root()
    internal = []
    for status in (root / "class/drm").glob("card*-eDP-*/status"):
        try:
            if status.read_text().strip() == "connected":
                internal.append(status.parent.name.partition("-")[2])
        except OSError:
            pass
    backlights = list((root / "class/backlight").glob("*"))
    for path in backlights:
        if shutil_which("brightnessctl") and (path / "max_brightness").is_file():
            connector = internal[0] if len(internal) == len(backlights) == 1 else ""
            devices.append(
                Device(
                    "backlight:" + path.name,
                    "brightnessctl",
                    connector,
                    path.name,
                    path.name,
                )
            )
    if shutil_which("ddcutil"):
        try:
            devices.extend(
                parse_ddc_detection(
                    command(["ddcutil", "detect", "--terse"], DETECT_TIMEOUT)
                )
            )
        except (OSError, subprocess.SubprocessError) as exc:
            ddc_ok = False
            LOG.warning("DDC discovery failed: %s", exc)
    # Ambiguous connectors are not exposed for per-monitor targeting.
    counts = {}
    labels = {}
    for device in devices:
        if device.connector:
            counts[device.connector] = counts.get(device.connector, 0) + 1
        if device.backend == "ddcutil":
            labels[device.label] = labels.get(device.label, 0) + 1
    found = {}
    for device in devices:
        serial = device.label.split(":")[-1].strip()
        has_serial = device.backend == "ddcutil" and device.label.count(":") >= 2
        has_serial = (
            has_serial and bool(serial) and serial.lower() not in ("unknown", "none")
        )
        has_serial = has_serial and not re.fullmatch(r"0+", serial)
        identity = ""
        if has_serial and labels[device.label] == 1:
            identity = "ddc:" + hashlib.sha256(device.label.encode()).hexdigest()
        found[device.id] = replace(
            device,
            connector=device.connector if counts.get(device.connector) == 1 else "",
            identity=identity,
        )
    return found, ddc_ok


def shutil_which(program):
    from shutil import which

    return which(program) is not None


def clamp(value):
    return max(0, min(100, value))


def initial_brightness(device):
    try:
        if device.backend == "brightnessctl":
            base = sys_root() / "class/backlight" / device.address
            maximum = int((base / "max_brightness").read_text())
            current = int((base / "brightness").read_text())
            minimum = BACKLIGHT_MIN if maximum > BACKLIGHT_MIN else 0
            return clamp(
                round((current - minimum) * 100 / max(1, maximum - minimum))
            ), maximum
        output = command(
            ["ddcutil", "--bus", device.address, "getvcp", "0x10", "--terse"],
            DDC_TIMEOUT,
        )
        # ddcutil's terse VCP response: VCP 10 C <current> <max>.
        match = re.search(r"\bVCP\s+10\s+C\s+(\d+)\s+(\d+)", output)
        if match and int(match.group(2)):
            maximum = int(match.group(2))
            return clamp(round(int(match.group(1)) * 100 / maximum)), maximum
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        LOG.warning("Cannot read %s: %s", device.id, exc)
    return None, device.raw_max


def set_brightness(device, value):
    if device.backend == "brightnessctl":
        base = sys_root() / "class/backlight" / device.address
        maximum = int((base / "max_brightness").read_text())
        minimum = BACKLIGHT_MIN if maximum > BACKLIGHT_MIN else 0
        raw = minimum + round(value * (maximum - minimum) / 100)
        command(["brightnessctl", "-d", device.address, "set", str(raw)], DDC_TIMEOUT)
        return
    # DDC writes on separate buses run concurrently, but never overlap on the same bus.
    for attempt in range(2):
        try:
            options = (
                ["--noverify", "--sleep-multiplier=0.6"]
                if attempt == 0
                else ["--sleep-multiplier=1.0"]
            )
            raw = round(value * device.raw_max / 100)
            command(
                [
                    "ddcutil",
                    "--bus",
                    device.address,
                    *options,
                    "setvcp",
                    "0x10",
                    str(raw),
                ],
                DDC_TIMEOUT,
            )
            return
        except (OSError, subprocess.SubprocessError):
            if attempt == 0:
                time.sleep(0.2)
            else:
                raise


class Controller:
    def __init__(self, root):
        self.root = root
        self.instance = secrets.token_hex(8)
        self.devices = {}
        self.levels = {}
        self.errors = {}
        self.pending = {}
        self.sequence = 0
        self.event = None
        self.lock = threading.RLock()
        self.wakeup = threading.Event()
        self.stopping = threading.Event()
        self.last_change = 0.0
        self.refresh_requested = True

    def publish(self):
        with self.lock:
            devices = [
                {
                    "id": d.id,
                    "backend": d.backend,
                    "connector": d.connector,
                    "label": d.label,
                    "value": self.levels.get(d.id),
                    "error": self.errors.get(d.id, ""),
                }
                for d in self.devices.values()
            ]
            state = {
                "version": 1,
                "instance": self.instance,
                "updatedAt": int(time.time() * 1000),
                "devices": devices,
                "sequence": self.sequence,
                "event": self.event,
            }
            json_write(self.root / "brightness.json", state)

    def scan(self, pool):
        found, _ = discover()
        with self.lock:
            previous = self.devices
            found = {
                key: previous[key]
                if key in previous
                and previous[key].address == device.address
                and previous[key].connector == device.connector
                and previous[key].label == device.label
                and previous[key].identity == device.identity
                else device
                for key, device in found.items()
            }
            changed = {
                key for key, device in found.items() if previous.get(key) != device
            }
            self.devices = found
            self.pending = {
                key: value
                for key, value in self.pending.items()
                if key in found and key not in changed
            }
            self.levels = {
                key: value
                for key, value in self.levels.items()
                if key in found and key not in changed
            }
            self.errors = {
                key: value for key, value in self.errors.items() if key in found
            }
        new = {
            key: pool.submit(initial_brightness, device)
            for key, device in found.items()
            if key in changed or self.levels.get(key) is None
        }
        for key, future in new.items():
            current, maximum = future.result()
            with self.lock:
                if self.devices.get(key) == found[key] and key not in self.pending:
                    self.devices[key] = replace(found[key], raw_max=maximum)
                    self.levels[key] = current
        self.publish()

    def target(self, selector):
        if selector == "all":
            return list(self.devices)
        matches = [
            d.id
            for d in self.devices.values()
            if selector in (d.id, d.connector) and selector
        ]
        if len(matches) != 1:
            raise ValueError("Unknown or ambiguous display: " + selector)
        return matches

    def request(self, payload):
        action = payload.get("action")
        if action == "list":
            with self.lock:
                return {
                    "ok": True,
                    "devices": [
                        {
                            "id": d.id,
                            "connector": d.connector,
                            "backend": d.backend,
                            "label": d.label,
                            "value": self.levels.get(d.id),
                        }
                        for d in self.devices.values()
                    ],
                }
        if action == "refresh":
            with self.lock:
                self.refresh_requested = True
            self.wakeup.set()
            return {"ok": True}
        if action not in ("set", "save", "restore"):
            raise ValueError("Invalid action")
        with self.lock:
            if action == "save":
                snapshot = {
                    (device.identity or key): self.levels[key]
                    for key, device in self.devices.items()
                    if (device.identity or device.backend == "brightnessctl")
                    and self.levels.get(key) is not None
                }
                if not snapshot:
                    raise ValueError("No displays with stable identities to save")
                json_write(state_dir() / "brightness-saved.json", snapshot)
                return {"ok": True}
            if action == "restore":
                try:
                    saved = json.loads(
                        (state_dir() / "brightness-saved.json").read_text()
                    )
                except (OSError, ValueError) as exc:
                    raise ValueError("No valid saved brightness levels") from exc
                values = {}
                for key, device in self.devices.items():
                    if not device.identity and device.backend != "brightnessctl":
                        continue
                    value = saved.get(device.identity or key)
                    if type(value) is int and 0 <= value <= 100:
                        values[key] = value
                if not values:
                    raise ValueError("No saved displays are connected")
                silent = True
                selector = "all"
            else:
                selector = payload.get("selector", "all")
                change = payload.get("change")
                if (
                    not isinstance(selector, str)
                    or not isinstance(change, str)
                    or not re.fullmatch(r"[+-]?\d{1,3}", change)
                ):
                    raise ValueError("Invalid brightness request")
                amount = int(change[1:] if change[0] in "+-" else change)
                if amount > 100:
                    raise ValueError("Brightness must be between 0 and 100")
                targets = self.target(selector)
                if not targets:
                    raise ValueError("No brightness devices available")
                values = {}
                for key in targets:
                    current = self.levels.get(key)
                    if change[0] in "+-":
                        if current is None:
                            raise ValueError("Brightness is unknown for " + key)
                        values[key] = clamp(
                            current + (amount if change[0] == "+" else -amount)
                        )
                    else:
                        values[key] = amount
                silent = bool(payload.get("silent", False))
            self.levels.update(values)
            self.pending.update(values)
            self.last_change = time.monotonic()
            if not silent:
                self.sequence += 1
                self.event = {
                    "selector": selector,
                    "value": values[next(iter(values))]
                    if len(set(values.values())) == 1
                    else None,
                }
            else:
                self.event = None
            self.publish()
            self.wakeup.set()
            return {"ok": True}

    def run(self):
        next_heartbeat = 0.0
        with ThreadPoolExecutor(max_workers=8) as pool:
            while not self.stopping.is_set():
                with self.lock:
                    scan_requested = self.refresh_requested
                    self.refresh_requested = False
                if scan_requested:
                    try:
                        self.scan(pool)
                    except (OSError, ValueError, subprocess.SubprocessError) as exc:
                        LOG.warning("Device scan failed: %s", exc)
                now = time.monotonic()
                if now >= next_heartbeat:
                    self.publish()
                    next_heartbeat = now + 2
                with self.lock:
                    ready = bool(self.pending) and now - self.last_change >= 0.1
                    work = self.pending.copy() if ready else {}
                    if ready:
                        self.pending.clear()
                if work:
                    with self.lock:
                        futures = {
                            key: pool.submit(set_brightness, self.devices[key], value)
                            for key, value in work.items()
                            if key in self.devices
                        }
                    for key, future in futures.items():
                        try:
                            future.result()
                            error = ""
                        except (OSError, ValueError, subprocess.SubprocessError) as exc:
                            error = str(exc)
                            LOG.warning("Cannot set %s: %s", key, exc)
                        with self.lock:
                            if key in self.devices:
                                if error:
                                    self.errors[key] = error
                                else:
                                    self.errors.pop(key, None)
                    self.publish()
                self.wakeup.wait(0.1 if self.pending else 0.5)
                self.wakeup.clear()


def serve(controller):
    root = controller.root
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(root, 0o700)
    lockfile = (root / "brightness.lock").open("w")
    try:
        fcntl.flock(lockfile, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as exc:
        lockfile.close()
        raise AlreadyRunning("Brightness daemon is already running") from exc
    path = root / "brightness.sock"
    path.unlink(missing_ok=True)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        server.bind(str(path))
        os.chmod(path, 0o600)
        server.listen(16)
        server.settimeout(0.5)
        worker = threading.Thread(target=controller.run, daemon=True)
        worker.start()

        def stop(*_):
            controller.stopping.set()

        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)
        while not controller.stopping.is_set():
            if not worker.is_alive():
                LOG.error("Brightness worker stopped; restarting")
                worker = threading.Thread(target=controller.run, daemon=True)
                worker.start()
            try:
                connection, _ = server.accept()
            except TimeoutError:
                continue
            with connection:
                connection.settimeout(2)
                try:
                    request = json.loads(connection.makefile("rb").readline(4096))
                    response = controller.request(request)
                except (ValueError, OSError, AttributeError) as exc:
                    response = {"ok": False, "error": str(exc)}
                try:
                    connection.sendall((json.dumps(response) + "\n").encode())
                except OSError:
                    pass
        worker.join(timeout=DDC_TIMEOUT * 2 + 2)
    finally:
        server.close()
        path.unlink(missing_ok=True)
        (root / "brightness.json").unlink(missing_ok=True)
        lockfile.close()


def send(payload):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(SOCKET_TIMEOUT)
        connection.connect(str(runtime_dir() / "brightness.sock"))
        connection.sendall((json.dumps(payload) + "\n").encode())
        response = json.loads(connection.makefile("rb").readline(65536))
        if not response.get("ok"):
            raise RuntimeError(response.get("error", "Brightness request failed"))
        return response


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "-m",
        "--monitor",
        default="all",
        help="DRM connector (DP-1, eDP-1) or device id",
    )
    parser.add_argument(
        "action", help="0..100, +N, -N, save, restore, dim, list, refresh, or daemon"
    )
    args = parser.parse_args()
    if args.action == "daemon":
        controller = Controller(runtime_dir())
        while True:
            try:
                serve(controller)
                return 0
            except AlreadyRunning as exc:
                LOG.info("%s", exc)
                return 2
            except RuntimeError as exc:
                LOG.error("%s", exc)
                return 1
            except Exception:
                LOG.exception("Daemon failed; retrying in three seconds")
                time.sleep(3)
                controller = Controller(runtime_dir())
    elif args.action == "list":
        print(json.dumps(send({"action": "list"})))
    elif args.action == "refresh":
        send({"action": "refresh"})
    elif args.action in ("save", "restore"):
        send({"action": args.action})
    elif args.action == "dim":
        send({"action": "set", "selector": args.monitor, "change": "0", "silent": True})
    elif re.fullmatch(r"[+-]?\d{1,3}", args.action):
        send({"action": "set", "selector": args.monitor, "change": args.action})
    else:
        parser.error("Expected a brightness change or command")
    return 0


if __name__ == "__main__":
    if "daemon" in sys.argv[1:]:
        log_path = state_dir() / "brightness.log"
        log_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        handlers = [RotatingFileHandler(log_path, maxBytes=1_000_000, backupCount=2)]
    else:
        handlers = [logging.StreamHandler()]
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        handlers=handlers,
    )
    try:
        sys.exit(main())
    except (TimeoutError, OSError, RuntimeError, ValueError) as error:
        print("brightness: " + str(error), file=sys.stderr)
        sys.exit(1)
