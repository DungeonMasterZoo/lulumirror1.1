"""Offline GPT identity checks; never accesses a device."""
import binascii
import importlib.util
import struct
import unittest
import uuid
from pathlib import Path

spec = importlib.util.spec_from_file_location("backup", Path(__file__).resolve().parents[1] / "scripts/backup-mirror-user.py")
backup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backup)


def fixture():
    data = bytearray(34 * 512)
    table = bytearray(128 * 128)
    entries = list(backup.EXPECTED.items())
    entries += [("userdata", (0xE4C000, 0xBB0000, str(uuid.uuid4())))]
    entries += [(f"other{i}", (0x1000 + i, 1, str(uuid.uuid4()))) for i in range(8)]
    for i, (name, (start, count, ident)) in enumerate(entries):
        offset = i * 128
        table[offset:offset + 16] = uuid.uuid4().bytes_le
        table[offset + 16:offset + 32] = uuid.UUID(ident).bytes_le
        struct.pack_into("<QQ", table, offset + 32, start, start + count - 1)
        name_bytes = name.encode("utf-16-le")
        table[offset + 56:offset + 56 + len(name_bytes)] = name_bytes
    h = bytearray(512)
    h[:8] = b"EFI PART"
    struct.pack_into("<I", h, 12, 92)
    struct.pack_into("<Q", h, 32, 30_000_000)
    struct.pack_into("<QIII", h, 72, 2, 128, 128, binascii.crc32(table))
    struct.pack_into("<I", h, 16, binascii.crc32(h[:92]))
    data[512:1024] = h
    data[1024:] = table
    return data


class GptChecks(unittest.TestCase):
    def test_matching_identity(self):
        self.assertIn("userdata", backup.validate_gpt(fixture(), 31_000_000 * 512))

    def test_rejects_corruption(self):
        data = fixture()
        data[1030] ^= 1
        with self.assertRaises(SystemExit):
            backup.validate_gpt(data, 31_000_000 * 512)

    def test_rejects_wrong_partition_identity(self):
        data = fixture()
        data[1024 + 16] ^= 1
        struct.pack_into("<I", data, 512 + 88, binascii.crc32(data[1024:]))
        data[512 + 16:512 + 20] = b"\0" * 4
        struct.pack_into("<I", data, 512 + 16, binascii.crc32(data[512:512 + 92]))
        with self.assertRaises(SystemExit):
            backup.validate_gpt(data, 31_000_000 * 512)


if __name__ == "__main__":
    unittest.main()
