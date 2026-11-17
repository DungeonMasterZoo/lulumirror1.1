#!/usr/bin/env python3
"""Set research-only options in an NXP 2020.04 Kconfig output.

Run olddefconfig afterward and verify the result; Kconfig may override these.
This configuration does not prevent flash commands or other persistent writes.
Source: https://github.com/nxp-imx/uboot-imx/tree/android-10.0.0_2.5.0
"""
import re
import sys
from pathlib import Path

config = Path(sys.argv[1])
mode = sys.argv[2] if len(sys.argv) > 2 else "research"
if mode not in ("research", "backup-ums", "backup-ums-direct") or len(sys.argv) > 3:
    raise SystemExit("Usage: configure-uboot-research.py CONFIG [research|backup-ums|backup-ums-direct]")
values = {
    "ENV_IS_IN_MMC": None,
    "ENV_IS_NOWHERE": "y",
    "CMD_SAVEENV": None,
    "USE_BOOTCOMMAND": "y",
    # In backup-ums mode, fastboot's normal cleanup runs before UMS starts.
    # UMS is writable and this behavior is untested on the target.
    "BOOTCOMMAND": {
        "research": '"fastboot 0"',
        "backup-ums": '"fastboot 0; ums 0 mmc 2"',
        "backup-ums-direct": '"ums 0 mmc 2"',
    }[mode],
    "BOOTDELAY": "0",
    # End exactly at the guide's FDT address (0x43000000). This is only
    # a static overlap reduction, not proof that U-Boot leaves this RAM free.
    "FASTBOOT_BUF_ADDR": "0x42800000",
    "FASTBOOT_BUF_SIZE": "0x800000",
}
lines = config.read_text().splitlines()
pattern = re.compile(r"^(?:# )?CONFIG_([A-Z0-9_]+)(?:=| is not set)")
lines = [line for line in lines if not ((match := pattern.match(line)) and match.group(1) in values)]
lines.extend(f"CONFIG_{name}={value}" if value is not None else f"# CONFIG_{name} is not set" for name, value in values.items())
config.write_text("\n".join(lines) + "\n")
