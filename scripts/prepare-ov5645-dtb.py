#!/usr/bin/env python3
"""Prepare a stock-OV5645-compatible Linux DTB locally; never contact the device."""
import hashlib
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
source = root / 'vendor/lemonademirror/prebuilt/imx8mm-mirror.dtb'
dtc = root / 'build/uboot-nxp-task.LHWaKn/scripts/dtc/dtc'
output = root / 'build/ov5645-persistent/imx8mm-mirror-ov5645.dtb'
expected = '1f0702287ff95611776b89f42c665684706ed8c025a9bb42292e4deffe15dc41'
if hashlib.sha256(source.read_bytes()).hexdigest() != expected:
    raise SystemExit('Unexpected source DTB')
if output.exists() or output.is_symlink():
    raise SystemExit(f'Refusing to overwrite {output}')

def decompile(path):
    return subprocess.run([str(dtc), '-q', '-I', 'dtb', '-O', 'dts', str(path)],
                          check=True, stdout=subprocess.PIPE).stdout.decode()

text = decompile(source)
start = text.index('\n\t\t\t\tcamera@3c {')
end = text.index('\n\t\t\ti2c@30a50000', start)
node = text[start:end]
changes = {
    'compatible = "ovti,ov5640";': 'compatible = "ovti,ov5645";',
    'powerdown-gpios = <0x28 0x7 0x0>;': 'enable-gpios = <0x28 0x7 0x0>;',
    'DOVDD-supply = <0x30>;': 'vdddo-supply = <0x30>;',
    'AVDD-supply = <0x31>;': 'vdda-supply = <0x31>;',
    'DVDD-supply = <0x32>;': 'vddd-supply = <0x32>;',
}
for old, new in changes.items():
    if node.count(old) != 1:
        raise SystemExit(f'Unexpected camera node: {old}')
    node = node.replace(old, new, 1)
modified = text[:start] + node + text[end:]
with tempfile.TemporaryDirectory(prefix='mirror-ov5645-dtb-') as tmp:
    dts, dtb = Path(tmp) / 'camera.dts', Path(tmp) / 'camera.dtb'
    dts.write_text(modified)
    cmd = [str(dtc), '-q', '-I', 'dts', '-O', 'dtb', '-o', str(dtb), str(dts)]
    print('Local command:', ' '.join(cmd), flush=True)
    subprocess.run(cmd, check=True)
    if decompile(dtb) != modified:
        raise SystemExit('DTB round-trip mismatch')
    data = dtb.read_bytes()
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('xb') as f:
        f.write(data)
print('Prepared:', output)
print('SHA-256:', hashlib.sha256(data).hexdigest())
print('Existing regulator phandles, pin groups and clock retained. Not installed.')
