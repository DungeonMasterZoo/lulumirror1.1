#!/usr/bin/env python3
"""Statically verify the experimental i.MX8M shim package; never boot it.

Header format and layout: NXP imx-mkimage iMX8M/mkimage_imx8.c,
https://github.com/nxp-imx/imx-mkimage/tree/1b577853ae1afe1f26cdef27548da52fb424af48
The guide describes the intended load and entry addresses:
https://failedattempts.neocities.org/part3a
Checks identify bytes and layout, not authenticity or device compatibility.
"""
import hashlib
import struct
import sys
from pathlib import Path

image = Path(sys.argv[1]).read_bytes()
payload = Path(sys.argv[2]).read_bytes()
expected_raw = "33b583d78c8b0b008d3645e9b65feb511253c6dff81b401d62d28bb6e57dd1e2"
if hashlib.sha256(payload).hexdigest() != expected_raw:
    raise ValueError("Raw shim differs from the recorded experimental build")
if len(image) < 64 + len(payload):
    raise ValueError("Image is too short")
header, entry, reserved1, dcd, boot_ptr, self_ptr, csf, reserved2 = struct.unpack_from("<8I", image)
start, size, plugin = struct.unpack_from("<3I", image, 32)
if (header, entry, reserved1, dcd, boot_ptr, self_ptr, reserved2) != (
    0x412000D1, 0x40000040, 0, 0, 0x40000020, 0x40000000, 0
):
    raise ValueError("Unexpected IVT fields")
if (start, size, plugin) != (0x3FFFFC00, 0x2A60, 0):
    raise ValueError("Unexpected NXP-generated boot-data fields")
if image[64:64 + len(payload)] != payload or any(image[64 + len(payload):]):
    raise ValueError("Payload mismatch or unexpected trailing content")
if csf != 0x40000600 or csf - self_ptr >= len(image):
    raise ValueError("Unexpected CSF pointer")
print(f"IVT tag/length/version: {image[:4].hex()}, entry={entry:#x}, self={self_ptr:#x}")
print(f"Payload at +0x40 matches {len(payload)} raw bytes; SHA-256={expected_raw}")
print(f"Boot data start={start:#x}, size={size:#x}; CSF pointer={csf:#x} points into zero padding")
print(f"Image SHA-256={hashlib.sha256(image).hexdigest()}; size={len(image)}")
print("Unsigned experimental image. Static layout checks only; do not send to a device.")
