#!/usr/bin/env python3
"""Test U-Boot environment encoding offline. Never writes to a device."""
import binascii
import hashlib
import struct
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
tool = root / "build/uboot-nxp-task.LHWaKn/tools/mkenvimage"
expected = "ccf5b2dfc0341913a85f53222b1a5ad687e9c13788f009fe85a968e19d5286cd"
if not tool.is_file() or hashlib.sha256(tool.read_bytes()).hexdigest() != expected:
    raise SystemExit("Expected locally built mkenvimage is missing or changed.")
bootcmd = "mmc dev 2; fatload mmc 2:4 0x40800000 /boot.scr; source 0x40800000"
with tempfile.TemporaryDirectory(prefix="mirror-env-test-") as d:
    text, image = Path(d) / "env.txt", Path(d) / "env.bin"
    text.write_text("bootcmd=" + bootcmd + "\n")
    cmd = [str(tool), "-s", "4096", "-o", str(image), str(text)]
    print("Local test command:", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True)
    raw = image.read_bytes()
    assert len(raw) == 4096
    assert struct.unpack_from("<I", raw)[0] == binascii.crc32(raw[4:])
    assert raw[4:].split(b"\0", 1)[0] == ("bootcmd=" + bootcmd).encode()
    print("PASS: mkenvimage generated a 4096-byte little-endian CRC-valid record containing the repo's boot command.")
    print("Test only: this minimal record omits other variables. No device or backup was modified.")
    print("This does not establish the actual stock environment location or justify writing this record.")
