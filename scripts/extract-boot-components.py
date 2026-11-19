#!/usr/bin/env python3
"""Extract the named boot components using the boot image's FIT metadata.

Background and provenance:
* Gouda-percha's guide identifies ATF, TEE, and a device tree as inputs for
  the RAM-only boot, but does not provide extraction commands:
  https://failedattempts.neocities.org/part3a
* LemonadeMirror explains that the signed boot chain is in the separate eMMC
  boot0 hardware partition and that its offsets can vary between builds:
  https://github.com/ikiiftekhar2/lemonademirror/blob/main/docs/boot-chain-anatomy.md
* A FIT (Flattened Image Tree) uses the device-tree binary format. The current
  format specification is linked from https://docs.u-boot.org/en/latest/usage/fit/
  and lives at https://fitspec.osfw.foundation/.

On the supplied reference image, inspecting the FIT at file offset 0x60000
showed external-data offsets for the named components. The device-tree payload
starts with the expected d00dfeed magic at 0x60000 + 0xdafd0 = 0x13afd0,
supporting the interpretation that those offsets are relative to the FIT base.
The script reads these values from the image each time; it does not hard-code
the observed offsets. That interpretation is validated only for this image,
not for every FIT variant or another MIRROR firmware build.

This extracts files locally; it neither communicates with nor modifies a MIRROR.
An extracted component is not automatically a compatible or trusted boot file.
"""

import argparse
import hashlib
import struct
from pathlib import Path


def read_fit_components(image):
    # The four-byte magic identifies a flattened device-tree header. Both the
    # outer FIT and the embedded device tree start with these bytes, so a magic
    # match alone does not identify the desired component table.
    magic = bytes.fromhex("d00dfeed")
    candidates = []
    start = 0
    while (offset := image.find(magic, start)) != -1:
        candidates.append(offset)
        start = offset + 1

    for base in candidates:
        try:
            # FDT header fields are 32-bit big-endian integers. Header offsets
            # are relative to the start of this candidate FIT, not the file.
            header = struct.unpack_from(">10I", image, base)
            _, total, struct_offset, strings_offset, _, _, _, _, strings_size, struct_size = header
            if total > len(image) - base or struct_offset + struct_size > total or strings_offset + strings_size > total:
                continue
            pos = base + struct_offset
            end = pos + struct_size
            strings = base + strings_offset
            stack = []
            nodes = {}
            # Walk the FDT structure block: 1 begins a node, 2 ends it,
            # 3 introduces a property, 4 is padding/NOP, and 9 ends the tree.
            # Property names are offsets into the separate strings block.
            while pos < end:
                token = struct.unpack_from(">I", image, pos)[0]
                pos += 4
                if token == 1:
                    name_end = image.index(0, pos, end)
                    stack.append(image[pos:name_end].decode("ascii"))
                    pos = (name_end + 4) & ~3
                elif token == 2:
                    stack.pop()
                elif token == 3:
                    length, name_offset = struct.unpack_from(">II", image, pos)
                    pos += 8
                    if name_offset >= strings_size or pos + length > end:
                        raise ValueError("Invalid FIT property bounds")
                    name_start = strings + name_offset
                    name_end = image.index(0, name_start, strings + strings_size)
                    name = image[name_start:name_end].decode("ascii")
                    nodes.setdefault("/".join(stack), {})[name] = image[pos:pos + length]
                    pos = (pos + length + 3) & ~3
                elif token == 4:
                    continue
                elif token == 9:
                    break
                else:
                    raise ValueError("Invalid FIT token")
            # These node names came from inspecting this reference image's FIT,
            # not from guesses about byte patterns in the binary payloads.
            required = {"u-boot-stock.bin": "/images/uboot@1", "atf.bin": "/images/atf@1", "tee.bin": "/images/tee@1", "fdt.dtb": "/images/fdt@1"}
            if not all(node in nodes for node in required.values()):
                continue
            result = {}
            for filename, node in required.items():
                props = nodes[node]
                # The FIT stores data-position and data-size for each payload.
                # For the supplied image, data-position is relative to the FIT
                # base. The table yielded the following observed values:
                #   uboot@1: 0x60000 + 0x3000 = 0x63000, size 0xd7fd0
                #   atf@1: 0x60000 + 0xe3b00 = 0x143b00, size 0xb1f0
                #   tee@1: 0x60000 + 0xeecf0 = 0x14ecf0, size 0x15ad10
                #   fdt@1: 0x60000 + 0xdafd0 = 0x13afd0, size 0x8b30
                # These are recorded for auditability, not used as constants.
                offset = struct.unpack(">I", props["data-position"])[0]
                size = struct.unpack(">I", props["data-size"])[0]
                absolute = base + offset
                if not size or absolute + size > len(image):
                    raise ValueError(f"{filename} is outside the image")
                data = image[absolute:absolute + size]
                if filename == "fdt.dtb":
                    # Independent sanity check: the selected payload must be
                    # an FDT and its declared length must fit in the payload.
                    dt_magic, dt_size = struct.unpack_from(">II", data)
                    if dt_magic != 0xD00DFEED or dt_size > len(data):
                        raise ValueError("Invalid device tree header")
                result[filename] = (absolute, data)
            return base, result
        except (ValueError, UnicodeDecodeError, struct.error, IndexError, KeyError):
            continue
    raise ValueError("No FIT containing the expected ATF, TEE, and FDT nodes found")


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", nargs="?", type=Path, default=root / "reference-images/mmcblk2boot0.img")
    parser.add_argument("--output", type=Path, default=root / "build/extracted-boot-components")
    args = parser.parse_args()

    image = args.image.read_bytes()
    base, components = read_fit_components(image)
    # Hashes make it possible to compare a future run against this source and
    # its outputs. They identify bytes; they do not authenticate their origin.
    print(f"Source: {args.image} ({len(image)} bytes)")
    print(f"Source SHA-256: {hashlib.sha256(image).hexdigest()}")
    print(f"FIT offset: {base:#x}")
    args.output.mkdir(parents=True, exist_ok=True)
    for filename, (offset, data) in components.items():
        destination = args.output / filename
        if destination.exists():
            # Re-running is safe when outputs match. Never replace different
            # data silently, including files that might be the user's work.
            if destination.read_bytes() != data:
                raise FileExistsError(f"Refusing to overwrite different file: {destination}")
            action = "verified existing"
        else:
            with destination.open("xb") as output:
                output.write(data)
            action = "extracted"
        print(f"{destination}: {action}, offset={offset:#x}, size={len(data)}, sha256={hashlib.sha256(data).hexdigest()}")


if __name__ == "__main__":
    main()
