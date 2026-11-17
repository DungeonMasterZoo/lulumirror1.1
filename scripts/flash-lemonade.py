#!/usr/bin/env python3
"""Verify local release and MIRROR disk, then run the upstream installer."""
import hashlib
import importlib.util
import os
import re
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
release = root / "build/lemonademirror-v1.0-kernel-6.18.60"
assets = {
    "flash-mirror.sh": "c332eaf3ee2aec9b79ce0165eba80384b8d431eaf0e37ca074a642b00d9a0220",
    "flash-mirror.py": "4723625e66e830296633e33409bac86b3b4ac9604404eecede728a1eb5a60502",
    "mirror-boot.img": "cfcb3476851c87da4ac895c9e3a72f1e6f3f95fa7bb28900be80c56fe3a7a1d2",
    "mirror-rootfs.img.xz": "c81fe11fbf5753c017fc1502b6a950e37212f8b16d49bf551f8fc83031c020c4",
}
for name, digest in assets.items():
    path = release / name
    if not path.is_file():
        raise SystemExit(f"STOPPED: missing {path}")
    with path.open("rb") as f:
        actual = hashlib.file_digest(f, "sha256").hexdigest()
    if actual != digest:
        raise SystemExit(f"STOPPED: release hash mismatch: {path}")
    print(f"Verified release file: {name}", flush=True)

if sys.argv[1:] == ["--check"]:
    print("Local checks only: no device accessed and no installer run.")
    raise SystemExit(0)
if len(sys.argv) != 2 or not re.fullmatch(r"disk[0-9]+", sys.argv[1]):
    raise SystemExit("Usage: mise run flash-lemonade -- diskN")
if not sys.stdin.isatty():
    raise SystemExit("Run interactively in your terminal.")
spec = importlib.util.spec_from_file_location("env_write", root / "scripts/write-usb-boot-test.py")
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
print("Command: sudo -v", flush=True)
subprocess.run(["sudo", "-v"], check=True)
disk = sys.argv[1]
raw = probe.validate_disk(disk)
read = ["sudo", "-n", "/bin/dd", f"if={raw}", "bs=4096", "skip=1024", "count=1"]
if hashlib.sha256(probe.run_read(read)).hexdigest() != probe.SHA:
    raise SystemExit("STOPPED: persistent USB test environment is not present at expected location.")
print(f"Verified {disk} and its existing USB boot test environment.", flush=True)
print("The installer will erase boot_b and userdata. It will prompt for settings and backup confirmation.", flush=True)
cmd = ["sudo", "/bin/sh", str(release / "flash-mirror.sh"), raw]
print("Command:", " ".join(cmd), flush=True)
os.execvp(cmd[0], cmd)
