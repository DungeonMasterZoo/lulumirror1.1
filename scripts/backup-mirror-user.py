#!/usr/bin/env python3
"""Copy the confirmed MIRROR user area to Downloads without writing the disk.

UMS guide: https://github.com/ikiiftekhar2/lemonademirror/blob/main/docs/06-flash-image.md
The host-visible UMS disk is writable: this script never opens it for writing,
but cannot prevent macOS or other processes from doing so. It does not back up
the separate boot0, boot1 or RPMB hardware partitions.
"""
import binascii
import hashlib
import os
import plistlib
import re
import shutil
import stat
import struct
import subprocess
import sys
import uuid
from pathlib import Path

SECTOR = 512
EXPECTED = {
    "boot_a": (0x8000, 0x20000, "6c567fe8-e957-4150-a9f5-d434dc2ddfdd"),
    "boot_b": (0x28000, 0x20000, "d92dba51-78f5-447b-8ac9-a1ed67a00269"),
    "super": (0x4C000, 0xE00000, "6b6aa24c-9186-40de-bbf8-acd977c1b776"),
}


def fail(message):
    raise SystemExit(f"STOPPED: {message}")


def disk_plist(*args):
    return plistlib.loads(subprocess.check_output(["diskutil", *args]))


def validate_gpt(data, disk_size):
    if len(data) < 34 * SECTOR:
        fail("short GPT read")
    h = data[SECTOR:2 * SECTOR]
    if h[:8] != b"EFI PART":
        fail("missing GPT header")
    hsize = struct.unpack_from("<I", h, 12)[0]
    if not 92 <= hsize <= SECTOR:
        fail("invalid GPT header size")
    check = bytearray(h[:hsize])
    check[16:20] = b"\0" * 4
    if binascii.crc32(check) != struct.unpack_from("<I", h, 16)[0]:
        fail("GPT header CRC mismatch")
    last = struct.unpack_from("<Q", h, 32)[0]
    if (last + 1) * SECTOR > disk_size:
        fail("GPT extends beyond device")
    lba, count, size, table_crc = struct.unpack_from("<QIII", h, 72)
    offset = lba * SECTOR
    length = count * size
    if size < 128 or count > 128 or offset < 2 * SECTOR or length == 0 or offset + length > len(data):
        fail("unexpected GPT entry layout")
    table = data[offset:offset + length]
    if binascii.crc32(table) != table_crc:
        fail("GPT table CRC mismatch")
    parts = {}
    for i in range(count):
        e = table[i * size:(i + 1) * size]
        if e[:16] == b"\0" * 16:
            continue
        first, last = struct.unpack_from("<QQ", e, 32)
        if last < first or (last + 1) * SECTOR > disk_size:
            fail("invalid GPT partition range")
        name = e[56:128].decode("utf-16-le").split("\0")[0]
        if name in parts:
            fail("duplicate GPT partition name")
        parts[name] = (first, last - first + 1, str(uuid.UUID(bytes_le=bytes(e[16:32]))))
    for name, expected in EXPECTED.items():
        if parts.get(name) != expected:
            fail(f"{name} does not match this MIRROR's observed partition identity")
    if "userdata" not in parts or len(parts) != 12:
        fail("unexpected Android partition layout")
    return parts


def dd_command(device, header=False):
    command = ["sudo", "-n", "/bin/dd", f"if={device}"]
    return command + (["bs=512", "count=34"] if header else ["bs=4m"])


def stream_disk(device, expected_size, output=None):
    digest = hashlib.sha256()
    total = 0
    cmd = dd_command(device)
    print("Reading source:", " ".join(cmd), flush=True)
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    try:
        while chunk := proc.stdout.read(4 * 1024 * 1024):
            total += len(chunk)
            if total > expected_size:
                fail("source produced more bytes than diskutil reported")
            digest.update(chunk)
            if output is not None:
                output.write(chunk)
            print(f"\r  {total / 1024**3:.2f} / {expected_size / 1024**3:.2f} GiB", end="", flush=True)
    except BaseException:
        proc.terminate()
        proc.wait()
        raise
    finally:
        proc.stdout.close()
    status = proc.wait()
    print()
    if status or total != expected_size:
        fail(f"source read failed or was incomplete (exit {status}, {total} of {expected_size} bytes)")
    return digest.hexdigest()


def main():
    if len(sys.argv) != 2 or not re.fullmatch(r"(?:/dev/)?(?:r)?disk[0-9]+", sys.argv[1]):
        fail("usage: mise run backup-copy -- diskN (whole USB disk only)")
    if not sys.stdin.isatty():
        fail("run interactively in your terminal")
    disk = re.search(r"disk[0-9]+$", sys.argv[1]).group()
    raw = f"/dev/r{disk}"
    print("Requesting administrator access for read-only disk reads.", flush=True)
    subprocess.run(["sudo", "-v"], check=True)
    info = disk_plist("info", "-plist", f"/dev/{disk}")
    size = info.get("TotalSize", 0)
    if info.get("DeviceIdentifier") != disk or not info.get("WholeDisk") or info.get("Internal") is not False:
        fail("source is not an external whole disk")
    if str(info.get("BusProtocol", "")).upper() != "USB" or not 14 * 1024**3 <= size <= 16 * 1024**3:
        fail("source is not a USB disk of the expected physical size")
    if not stat.S_ISCHR(os.stat(raw).st_mode):
        fail("raw source is not a character device")
    listing = disk_plist("list", "-plist", f"/dev/{disk}")
    disks = listing.get("AllDisksAndPartitions", [])
    if len(disks) != 1 or disks[0].get("DeviceIdentifier") != disk:
        fail("could not confirm selected disk layout")
    for ident in listing.get("AllDisks", []):
        child = disk_plist("info", "-plist", f"/dev/{ident}")
        if child.get("MountPoint"):
            fail(f"{ident} is mounted; do not copy until the disk is unmounted")
    print("Checking GPT through a read-only source command:", " ".join(dd_command(raw, True)), flush=True)
    header = subprocess.run(dd_command(raw, True), stdout=subprocess.PIPE, check=True).stdout
    validate_gpt(header, size)
    print(f"Verified external USB {disk}: {size} bytes; GPT CRCs and observed MIRROR partition identifiers match.")
    dest = Path.home() / "Downloads" / "mirror-backup"
    if dest.is_symlink():
        fail("backup destination is a symlink")
    dest.mkdir(mode=0o700, parents=True, exist_ok=True)
    if not dest.is_dir():
        fail("backup destination is not a directory")
    if shutil.disk_usage(dest).free < size + 1024**3:
        fail("not enough free destination space for the image plus 1 GiB margin")
    partial = dest / "mirror-user-area.img.partial"
    final = dest / "mirror-user-area.img"
    if partial.exists() or final.exists() or partial.is_symlink() or final.is_symlink():
        fail("backup or partial backup already exists; refusing to overwrite")
    if input(f"Type BACK UP {disk} to copy the entire user area: ") != f"BACK UP {disk}":
        fail("not confirmed")
    with partial.open("xb") as output:
        first_hash = stream_disk(raw, size, output)
        output.flush()
        os.fsync(output.fileno())
    print("Hashing the completed backup file...")
    with partial.open("rb") as f:
        file_hash = hashlib.file_digest(f, "sha256").hexdigest()
    if file_hash != first_hash:
        fail(f"backup-file hash mismatch; retained {partial}")
    print("Reading the source a second time for verification...")
    # The first full read can outlast sudo's timestamp. Refresh interactively.
    subprocess.run(["sudo", "-v"], check=True)
    second_hash = stream_disk(raw, size)
    if first_hash != second_hash:
        fail(f"source changed or read mismatch; retained {partial}")
    # Hard-link creation is atomic and fails if final already exists.
    os.link(partial, final)
    partial.unlink()
    print(f"Verified backup: {final}\nBytes: {size}\nSHA-256: {first_hash}")
    print("User area only: boot0, boot1 and RPMB are not included. Keep another copy.")


if __name__ == "__main__":
    main()
