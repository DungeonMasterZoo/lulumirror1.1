#!/usr/bin/env python3
"""Reproduce the two shim source files published in Gouda-percha's guide.

Source: https://failedattempts.neocities.org/part3a, sections "shim.c" and
"atf_common.h". The pinned SHA-256 digests below identify the exact source
blocks retrieved on 2026-11-08. They do not authenticate the author's site.
If the source changes, this script stops instead of silently building new code.

This adds repository-specific provenance comments after validating the original
source text. It does not compile, execute or send device code.
The guide's exact compiler versions and mkimage_imx8 build are not specified,
so reproducible binary generation still requires those details.
"""

import hashlib
from html.parser import HTMLParser
from pathlib import Path
from urllib.request import urlopen

URL = "https://failedattempts.neocities.org/part3a"
FILES = {
    "shim.c": ("#include \"atf_common.h\"", "f2929e55ae75d395010517f9ad1c1d9241d76dab6e2a945291682cc42d5911d7"),
    "atf_common.h": ("typedef unsigned char uint8_t;", "dacfe1312248b976623f0f88074cbee9db61306c77b34fbe6979d0e325ae8b45"),
}

# Keep these headers synchronized with the checked-in source files. The hashes
# above apply to the original guide blocks, before these explanatory comments.
HEADERS = {
    "shim.c": """/*
 * Provenance: Gouda-percha's RAM-only boot guide, shim.c section:
 * https://failedattempts.neocities.org/part3a
 *
 * This shim constructs the ATF handoff parameters and jumps to BL31 after
 * the guide's USB-loaded boot components are placed at their expected RAM
 * addresses. UART writes below are diagnostic output, not a USB console.
 * Addresses and hardware assumptions are from the author's example and have
 * not been verified for this unit. This is experimental; do not deploy it.
 * The repository's get-shim-source.py verifies the unmodified upstream block
 * and prepends this explanatory header when reproducing this file.
 */
""",
    "atf_common.h": """/*
 * Provenance: Gouda-percha's RAM-only boot guide, atf_common.h section:
 * https://failedattempts.neocities.org/part3a
 *
 * These types, constants and parameter structures support the shim's ATF
 * handoff. Their ABI layout must match the target firmware; this copy has not
 * been validated on this MIRROR. See https://trustedfirmware-a.readthedocs.io/
 * for the Trusted Firmware-A project; this file is the guide's example, not
 * a claim that it matches current TF-A headers.
 * The repository's get-shim-source.py verifies the unmodified upstream block
 * and prepends this explanatory header when reproducing this file.
 */
""",
}


class Blocks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.active = False
        self.current = []
        self.blocks = []

    def handle_starttag(self, tag, attrs):
        if tag == "pre":
            self.active = True
            self.current = []

    def handle_endtag(self, tag):
        if tag == "pre" and self.active:
            self.blocks.append("".join(self.current))
            self.active = False

    def handle_data(self, data):
        if self.active:
            self.current.append(data)


def main():
    with urlopen(URL, timeout=30) as response:
        html = response.read().decode("utf-8")
    parser = Blocks()
    parser.feed(html)
    selected = {}
    for name, (prefix, expected) in FILES.items():
        matches = [block for block in parser.blocks if block.startswith(prefix)]
        if len(matches) != 1:
            raise ValueError(f"Expected one source block for {name}; found {len(matches)}")
        data = matches[0].encode("utf-8")
        digest = hashlib.sha256(data).hexdigest()
        if digest != expected:
            raise ValueError(f"Source for {name} changed: {digest}; review before proceeding")
        selected[name] = HEADERS[name].encode("utf-8") + data

    target = Path(__file__).resolve().parent.parent / "shim"
    target.mkdir(exist_ok=True)
    for name, data in selected.items():
        path = target / name
        if path.exists():
            if path.read_bytes() != data:
                raise FileExistsError(f"Refusing to overwrite different file: {path}")
            action = "verified existing"
        else:
            with path.open("xb") as output:
                output.write(data)
            action = "saved"
        print(f"{path}: {action}, sha256={hashlib.sha256(data).hexdigest()}")


if __name__ == "__main__":
    main()
