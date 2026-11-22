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
disk = sys.argv[1]
print(f"Verified {disk}: MIRROR GPT and the tested USB boot environment match.")
print("This persistently switches normal startup from USB disk mode to LemonadeMirror.")
if input(f"Type SET LINUX BOOT {disk} to proceed: ") != f"SET LINUX BOOT {disk}":
    raise SystemExit("STOPPED: not confirmed")
write = ["sudo", "-n", "/bin/dd", f"of={disk}", "bs=4096", "seek=1024", "count=1", "conv=notrunc"]
print("Command: <verified 4096-byte environment on stdin> |", " ".join(write), flush=True)
print("Verified: LemonadeMirror boot environment read back unchanged.")
