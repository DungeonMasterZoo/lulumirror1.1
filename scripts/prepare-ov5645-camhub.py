#!/usr/bin/env python3
"""Prepare sensor-aware camera hub scripts from pinned release files."""
import hashlib
from pathlib import Path

root = Path(__file__).resolve().parent.parent
src = root / 'vendor/lemonademirror/rootfs/overlay/usr/local/sbin'
out = root / 'build/ov5645-persistent'
hub = (src / 'camhub.sh').read_text()
camset = (src / 'camset.sh').read_text()
old = "grep -q 'entity.*ov5640'"
if hub.count(old) != 1:
    raise SystemExit('Unexpected upstream camhub')
hub = hub.replace(old, "grep -Eq 'entity.*ov564[05]'", 1)
old = '''media-ctl -d $M -l '"ov5640 2-003c":0 -> "csis-32e30000.mipi-csi":0 [1]'
media-ctl -d $M -V "\\"ov5640 2-003c\\":0 [fmt:UYVY8_1X16/$R@1/$F]"'''
new = '''if media-ctl -d "$M" -p | grep -q 'entity.*ov5645 2-003c'; then
  SENSOR=ov5645
  INTERVAL=
else
  SENSOR=ov5640
  INTERVAL=@1/$F
fi
media-ctl -d "$M" -l "\\"$SENSOR 2-003c\\":0 -> \\\"csis-32e30000.mipi-csi\\\":0 [1]"
media-ctl -d "$M" -V "\\"$SENSOR 2-003c\\":0 [fmt:UYVY8_1X16/$R$INTERVAL]"'''
if camset.count(old) != 1:
    raise SystemExit('Unexpected upstream camset')
camset = camset.replace(old, new, 1)
out.mkdir(parents=True, exist_ok=True)
for name, content in [('camhub.sh', hub), ('camset.sh', camset)]:
    path = out / name
    with path.open('x') as f:
        f.write(content)
    print(name, hashlib.sha256(content.encode()).hexdigest())
print('Local candidates only; not installed.')
