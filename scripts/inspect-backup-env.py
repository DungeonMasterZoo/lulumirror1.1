#!/usr/bin/env python3
"""Find possible CRC-valid U-Boot environments in a backup, read-only."""
import mmap
import struct
import sys
import zlib
from pathlib import Path

IMAGE = Path.home() / "Downloads/mirror-backup/mirror-user-area.img"
EXPECTED_SIZE = 15653142528
SIZES = (4096, 8192, 16384, 32768, 65536, 131072, 262144)


def scan(path):
    found = set()
    with path.open("rb") as f, mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as data:
        pos = 0
        while (pos := data.find(b"bootcmd=", pos)) != -1:
            # Try common sector-aligned boundaries and normal/redundant headers.
            if pos and data[pos - 1] != 0 and pos % 512 not in (4, 5):
                pos += 8
                continue
            for size in SIZES:
                start = max(0, ((pos - size + 512) // 512) * 512)
                for off in range(start, pos + 1, 512):
                    if off + size > len(data):
                        break
                    expected = struct.unpack_from("<I", data, off)[0]
                    for header in (4, 5):
                        if pos < off + header or (off, size, header) in found:
                            continue
                        if zlib.crc32(data[off + header:off + size]) == expected:
                            found.add((off, size, header))
                            print(f"CRC-valid candidate: offset {off} (0x{off:x}), size {size}, header {header} bytes", flush=True)
            pos += 8
    return found


def main():
    if sys.argv[1:] not in ([], ["--check"]):
        raise SystemExit("Usage: mise run inspect-backup-env [--check]")
    if not IMAGE.is_file() or IMAGE.stat().st_size != EXPECTED_SIZE:
        raise SystemExit(f"Expected backup of {EXPECTED_SIZE} bytes not found: {IMAGE}")
    print(f"Read-only input: {IMAGE}")
    print("Search: sector-aligned, little-endian CRC32, 4- or 5-byte header, common 4 KiB to 256 KiB sizes.")
    print("The whole 14.58 GiB image will be read; no device is contacted and values are not printed.")
    if sys.argv[1:] == ["--check"]:
        return
    print("Scanning; this may take several minutes...", flush=True)
    found = scan(IMAGE)
    print(f"Finished: {len(found)} candidate(s). A match does not prove stock U-Boot uses it.")
    print("No match does not exclude boot0, boot1, RPMB, or an unsupported format.")


if __name__ == "__main__":
    main()
