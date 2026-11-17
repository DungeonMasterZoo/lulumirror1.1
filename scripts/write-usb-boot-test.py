#!/usr/bin/env python3
"""Write one approved 4 KiB test environment to the MIRROR user area."""
import hashlib
import importlib.util
import os
import re
import stat
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CANDIDATE = ROOT / "build/usb-boot-test-env.bin"
BACKUP = Path.home() / "Downloads/mirror-backup/mirror-user-area.img"
SHA = "c2bb365e10af1de69291b93c306e0588f520a6c2668f1c93fc4d157ffec1fa30"
SIZE, OFFSET = 15653142528, 0x400000
spec = importlib.util.spec_from_file_location("mirror_backup", ROOT / "scripts/backup-mirror-user.py")
backup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backup)


def stop(message):
    raise SystemExit("STOPPED: " + message)


def run_read(command):
    print("Command:", " ".join(command), flush=True)
    return subprocess.run(command, check=True, stdout=subprocess.PIPE).stdout


def validate_disk(disk):
    raw = f"/dev/r{disk}"
    info = backup.disk_plist("info", "-plist", f"/dev/{disk}")
    if (info.get("DeviceIdentifier") != disk or not info.get("WholeDisk") or
            info.get("Internal") is not False or str(info.get("BusProtocol", "")).upper() != "USB" or
            info.get("TotalSize") != SIZE or not stat.S_ISCHR(os.stat(raw).st_mode)):
        stop("not the expected external whole USB disk")
    listing = backup.disk_plist("list", "-plist", f"/dev/{disk}")
    disks = listing.get("AllDisksAndPartitions", [])
    if len(disks) != 1 or disks[0].get("DeviceIdentifier") != disk:
        stop("could not confirm disk layout")
    for ident in listing.get("AllDisks", []):
        if backup.disk_plist("info", "-plist", f"/dev/{ident}").get("MountPoint"):
            stop(f"{ident} is mounted")
    header = run_read(["sudo", "-n", "/bin/dd", f"if={raw}", "bs=512", "count=34"])
    parts = backup.validate_gpt(header, SIZE)
    if any(first * 512 < OFFSET + 4096 and (first + length) * 512 > OFFSET
           for first, length, _ in parts.values()):
        stop("candidate overlaps a GPT partition")
    return raw


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--check":
        candidate = CANDIDATE.read_bytes()
        if len(candidate) != 4096 or hashlib.sha256(candidate).hexdigest() != SHA:
            stop("candidate mismatch")
        print("Local candidate verified. No device accessed or written.")
        return
    if len(sys.argv) != 2 or not re.fullmatch(r"disk[0-9]+", sys.argv[1]):
        stop("usage: mise run write-usb-boot-test -- diskN")
    if not sys.stdin.isatty():
        stop("run interactively in your terminal")
    disk = sys.argv[1]
    candidate = CANDIDATE.read_bytes()
    if len(candidate) != 4096 or hashlib.sha256(candidate).hexdigest() != SHA:
        stop("candidate mismatch")
    if not BACKUP.is_file() or BACKUP.stat().st_size != SIZE:
        stop("verified backup missing or unexpected size")
    with BACKUP.open("rb") as f:
        f.seek(OFFSET)
        saved = f.read(4096)
    if saved != bytes(4096):
        stop("backup's original 4 KiB is not the expected zero bytes")
    print("Command: sudo -v", flush=True)
    subprocess.run(["sudo", "-v"], check=True)
    raw = validate_disk(disk)
    read = ["sudo", "-n", "/bin/dd", f"if={raw}", "bs=4096", "skip=1024", "count=1"]
    if run_read(read) != saved:
        stop("live original bytes do not match the backup")
    print(f"Verified {disk}: matching MIRROR GPT and original 4 KiB at 0x{OFFSET:x}.")
    print("This writes a persistent test environment: bootcmd=ums 0 mmc 2.")
    print("The test may change normal startup and expose writable USB storage.")
    if input(f"Type WRITE TEST {disk} to proceed: ") != f"WRITE TEST {disk}":
        stop("not confirmed")
    # Recheck identity and original immediately before writing.
    validate_disk(disk)
    if run_read(read) != saved:
        stop("original bytes changed before the write")
    write = ["sudo", "-n", "/bin/dd", f"of={raw}", "bs=4096", "seek=1024", "count=1", "conv=notrunc"]
    print("Command: <verified 4096-byte candidate on stdin> |", " ".join(write), flush=True)
    try:
        subprocess.run(write, input=candidate, check=True)
        if run_read(read) != candidate:
            stop("readback mismatch after write; do not repeat or reboot before review")
    except BaseException:
        print("Write or verification failed; do not repeat or reboot before reviewing the output.", file=sys.stderr)
        raise
    print("Verified: the 4 KiB candidate was read back unchanged. Do not flash LemonadeMirror yet.")
    print("Share this output before power-cycling; original bytes are in the verified backup.")


if __name__ == "__main__":
    main()
