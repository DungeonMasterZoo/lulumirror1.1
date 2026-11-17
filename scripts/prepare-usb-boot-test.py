#!/usr/bin/env python3
"""Prepare an offline-only candidate stock U-Boot environment, never deploy it."""
import binascii
import hashlib
import struct
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
stock = root / "build/extracted-boot-components/u-boot-stock.bin"
tool = root / "build/uboot-nxp-task.LHWaKn/tools/mkenvimage"
out = root / "build/usb-boot-test-env.bin"
backup = Path.home() / "Downloads/mirror-backup/mirror-user-area.img"
expected = {
    stock: "fd1329c1cd65a24068072365d725edd69839b78a50dfedb980f88a2275d610d9",
    tool: "ccf5b2dfc0341913a85f53222b1a5ad687e9c13788f009fe85a968e19d5286cd",
}
for path, digest in expected.items():
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        raise SystemExit(f"Missing or changed input: {path}")
defaults = [
    "bootdelay=2", "baudrate=115200", "ethprime=FEC", "loadaddr=0x40480000",
    "splashpos=m,m", "splashimage=0x50000000", "fdt_high=0xffffffffffffffff",
    "initrd_high=0xffffffffffffffff",
]
blob = b"\0".join(s.encode() for s in defaults) + b"\0\0"
data = stock.read_bytes()
if data.count(blob) != 1:
    raise SystemExit("Expected stock default environment not found exactly once.")
if not backup.is_file() or backup.stat().st_size != 15653142528:
    raise SystemExit("Verified user-area backup is missing or unexpected size.")
with backup.open("rb") as f:
    f.seek(0x400000)
    original = f.read(4096)
if original != bytes(4096):
    raise SystemExit("Candidate offset in the backup is not all zero; stop.")
if out.exists() or out.is_symlink():
    raise SystemExit(f"Refusing to overwrite existing output: {out}")
with tempfile.TemporaryDirectory(prefix="mirror-env-candidate-") as d:
    text, image = Path(d) / "env.txt", Path(d) / "env.bin"
    text.write_text("\n".join(defaults + ["bootcmd=ums 0 mmc 2"]) + "\n")
    cmd = [str(tool), "-s", "4096", "-o", str(image), str(text)]
    print("Local command:", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True)
    raw = image.read_bytes()
    if len(raw) != 4096 or struct.unpack_from("<I", raw)[0] != binascii.crc32(raw[4:]):
        raise SystemExit("Candidate CRC or size failed verification.")
    entries = raw[4:].split(b"\0\0", 1)[0].split(b"\0")
    if set(entries) != {s.encode() for s in defaults + ["bootcmd=ums 0 mmc 2"]}:
        raise SystemExit("Candidate entries do not match expected values.")
    with out.open("xb") as f:
        f.write(raw)
print(f"Candidate: {out}")
print(f"SHA-256: {hashlib.sha256(raw).hexdigest()}")
print("Candidate bootcmd: ums 0 mmc 2")
print("Offline only: no device was contacted or written. Do not write this image without a reviewed plan.")
print("A valid CRC and matching defaults do not prove that stock U-Boot uses the proposed offset.")
