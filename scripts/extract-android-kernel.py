#!/usr/bin/env python3
"""Extract this MIRROR's stock Android kernel from its backup, read-only."""
import hashlib
import struct
from pathlib import Path

backup = Path.home() / 'Downloads/mirror-backup/mirror-user-area.img'
out = Path(__file__).resolve().parent.parent / 'build/android-camera-analysis'
with backup.open('rb') as f:
    f.seek(512)
    header = f.read(512)
    if header[:8] != b'EFI PART':
        raise SystemExit('Invalid GPT')
    table_lba, count, size = struct.unpack_from('<QII', header, 72)
    if count > 128 or size != 128:
        raise SystemExit('Unexpected GPT layout')
    f.seek(table_lba * 512)
    table = f.read(count * size)
    entries = [table[i:i + size] for i in range(0, len(table), size)]
    boot = [e for e in entries if e[56:128].decode('utf-16-le').split('\0')[0] == 'boot_a']
    if len(boot) != 1 or struct.unpack_from('<QQ', boot[0], 32) != (0x8000, 0x27fff):
        raise SystemExit('Unexpected boot_a location')
    start = 0x8000 * 512
    f.seek(start)
    hdr = f.read(2048)
    if hdr[:8] != b'ANDROID!' or struct.unpack_from('<I', hdr, 36)[0] != 2048:
        raise SystemExit('Unexpected Android boot image')
    length = struct.unpack_from('<I', hdr, 8)[0]
    if not 0 < length <= 64 * 1024 * 1024 - 2048:
        raise SystemExit('Invalid kernel length')
    data = f.read(length)
    if len(data) != length or data[56:60] != b'ARM\x64':
        raise SystemExit('Invalid ARM64 kernel image')
out.mkdir(parents=True, exist_ok=True)
path = out / 'android-boot-a-Image'
with path.open('xb') as f:
    f.write(data)
print('Extracted:', path)
print('Size:', len(data), 'SHA-256:', hashlib.sha256(data).hexdigest())
print('Backup opened read-only; no device contacted.')
