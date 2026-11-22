#!/usr/bin/env python3
"""Replace the verified U-Boot USB test command with LemonadeMirror's command."""
import binascii
import hashlib
import importlib.util
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("env_write", root / "scripts/write-usb-boot-test.py")
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

test = probe.CANDIDATE.read_bytes()
if len(test) != 4096 or hashlib.sha256(test).hexdigest() != probe.SHA:
    raise SystemExit("STOPPED: test environment is missing or changed")
if int.from_bytes(test[:4], "little") != binascii.crc32(test[4:]):
    raise SystemExit("STOPPED: test environment CRC mismatch")
old = b"bootcmd=ums 0 mmc 2"
new = b"bootcmd=mmc dev 2; fatload mmc 2:4 0x40800000 /boot.scr; source 0x40800000"
payload = test[4:]
end = payload.find(b"\0\0")
if end < 0:
    raise SystemExit("STOPPED: malformed environment")
entries = payload[:end].split(b"\0")
if entries.count(old) != 1 or sum(x.startswith(b"bootcmd=") for x in entries) != 1:
    raise SystemExit("STOPPED: unexpected test boot command")
entries[entries.index(old)] = new
content = b"\0".join(entries) + b"\0\0"
if len(content) > len(payload):
    raise SystemExit("STOPPED: environment too large")
content += b"\xff" * (len(payload) - len(content))
candidate = binascii.crc32(content).to_bytes(4, "little") + content
digest = hashlib.sha256(candidate).hexdigest()
print("New boot command:", new.decode(), flush=True)
print("New environment SHA-256:", digest, flush=True)
if sys.argv[1:] == ["--check"]:
    print("Local check passed. No device accessed or written.")
    raise SystemExit(0)
if len(sys.argv) != 2 or not __import__("re").fullmatch(r"disk[0-9]+", sys.argv[1]):
    raise SystemExit("Usage: mise run set-lemonade-boot -- diskN")
if not sys.stdin.isatty():
    raise SystemExit("Run interactively in your terminal.")
disk = sys.argv[1]
print("Command: sudo -v", flush=True)
subprocess.run(["sudo", "-v"], check=True)
raw = probe.validate_disk(disk)
read = ["sudo", "-n", "/bin/dd", f"if={raw}", "bs=4096", "skip=1024", "count=1"]
if probe.run_read(read) != test:
    raise SystemExit("STOPPED: live environment does not match the verified USB test setting")
print(f"Verified {disk}: MIRROR GPT and the tested USB boot environment match.")
print("This persistently switches normal startup from USB disk mode to LemonadeMirror.")
if input(f"Type SET LINUX BOOT {disk} to proceed: ") != f"SET LINUX BOOT {disk}":
    raise SystemExit("STOPPED: not confirmed")
probe.validate_disk(disk)
if probe.run_read(read) != test:
    raise SystemExit("STOPPED: environment changed before write")
write = ["sudo", "-n", "/bin/dd", f"of={raw}", "bs=4096", "seek=1024", "count=1", "conv=notrunc"]
print("Command: <verified 4096-byte environment on stdin> |", " ".join(write), flush=True)
try:
    subprocess.run(write, input=candidate, check=True)
    if probe.run_read(read) != candidate:
        raise RuntimeError("readback mismatch")
except BaseException:
    print("Write or verification failed. Do not retry or reboot; share the output.", file=sys.stderr)
    raise
print("Verified: LemonadeMirror boot environment read back unchanged.")
print("Share the output before power-cycling.")
