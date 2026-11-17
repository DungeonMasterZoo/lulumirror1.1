#!/usr/bin/env python3
"""Build an offline device-tree candidate for the original camera clock."""
import hashlib
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
source = root / "vendor/lemonademirror/prebuilt/imx8mm-mirror.dtb"
dtc = root / "build/uboot-nxp-task.LHWaKn/scripts/dtc/dtc"
out = root / "build/camera-clko1-test.dtb"
expected = "1f0702287ff95611776b89f42c665684706ed8c025a9bb42292e4deffe15dc41"
if not source.is_file() or hashlib.sha256(source.read_bytes()).hexdigest() != expected:
    raise SystemExit("STOPPED: unexpected reference device tree")
if not dtc.is_file():
    raise SystemExit("STOPPED: local device-tree compiler missing")
if out.exists() or out.is_symlink():
    raise SystemExit(f"STOPPED: refusing to overwrite {out}")

def decompile(path):
    return subprocess.run([str(dtc), "-q", "-I", "dtb", "-O", "dts", str(path)],
                          check=True, stdout=subprocess.PIPE).stdout.decode()

text = decompile(source)
start = text.find("camera@3c {")
end = text.find("\n\t\t\ti2c@30a50000", start)
if start < 0 or end < 0:
    raise SystemExit("STOPPED: expected camera node not found")
node = text[start:end]
old = 'clocks = <0x2 0x2>;\n\t\t\t\t\tclock-names = "xclk";'
new = ('clocks = <0x2 0x9e>;\n\t\t\t\t\tclock-names = "xclk";\n'
       '\t\t\t\t\tassigned-clocks = <0x2 0x9e>;\n'
       '\t\t\t\t\tassigned-clock-parents = <0x2 0x2>;\n'
       '\t\t\t\t\tassigned-clock-rates = <0x16e3600>;')
if node.count(old) != 1:
    raise SystemExit("STOPPED: unexpected clock properties")
modified = text[:start] + node.replace(old, new, 1) + text[end:]
with tempfile.TemporaryDirectory(prefix="mirror-camera-dt-") as d:
    dts, dtb = Path(d) / "candidate.dts", Path(d) / "candidate.dtb"
    dts.write_text(modified)
    cmd = [str(dtc), "-q", "-I", "dts", "-O", "dtb", "-o", str(dtb), str(dts)]
    print("Local command:", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True)
    roundtrip = decompile(dtb)
    if roundtrip != modified:
        raise SystemExit("STOPPED: recompiled tree differs from intended properties")
    data = dtb.read_bytes()
    with out.open("xb") as f:
        f.write(data)
print("Offline candidate:", out)
print("SHA-256:", hashlib.sha256(data).hexdigest())
print("Only camera clock and its parent/rate were changed; supply mappings are unchanged.")
print("Not deployed or tested. This does not prove CLKO1 reaches the camera pin.")
