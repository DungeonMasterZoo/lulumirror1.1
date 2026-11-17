#!/usr/bin/env python3
"""Sample debugfs while retrying one unbound OV5640 probe; no storage writes."""
import errno
import os
import re
import threading
import time
from pathlib import Path

gpio = Path('/sys/kernel/debug/gpio')
clocks = Path('/sys/kernel/debug/clk/clk_summary')
device = Path('/sys/bus/i2c/devices/2-003c')
bind = Path('/sys/bus/i2c/drivers/ov5640/bind')
if os.geteuid() != 0:
    raise SystemExit('STOPPED: root required')
if not all(p.exists() for p in (gpio, clocks, device, bind)):
    raise SystemExit('STOPPED: required debugfs, camera device, or bind interface missing')
if (device / 'driver').is_symlink():
    raise SystemExit('STOPPED: camera is already bound; no probe attempted')

start = time.monotonic()
done = threading.Event()
seen = {'gpio': None, 'clock': None}
counts = {'gpio': 0, 'clock': 0}
events = []
lock = threading.Lock()
result = []


def record(kind, value):
    with lock:
        counts[kind] += 1
        if value != seen[kind]:
            events.append((time.monotonic() - start, kind, value))
            seen[kind] = value


def gpio_sample():
    while not done.is_set():
        try:
            text = gpio.read_text()
            bank = text.split('gpiochip0:', 1)[1].split('gpiochip1:', 1)[0]
            lines = [line.strip() for line in bank.splitlines()
                     if re.search(r'\bgpio-(?:6|7)\s', line)]
            record('gpio', ' | '.join(lines) or '(GPIO 6 and 7 unclaimed)')
        except (OSError, IndexError) as e:
            record('gpio', 'read error: ' + str(e))
        time.sleep(0.002)


def clock_sample():
    while not done.is_set():
        try:
            lines = [line.strip() for line in clocks.read_text().splitlines()
                     if re.match(r'^\s*(?:clko1|osc_24m)\s', line)]
            record('clock', ' | '.join(lines) or '(clock rows unavailable)')
        except OSError as e:
            record('clock', 'read error: ' + str(e))
        time.sleep(0.005)


threads = [threading.Thread(target=gpio_sample), threading.Thread(target=clock_sample)]
for thread in threads:
    thread.start()
try:
    time.sleep(0.2)
    print('Command: write 2-003c to /sys/bus/i2c/drivers/ov5640/bind', flush=True)
    before = time.monotonic() - start
    try:
        # TextIOWrapper may retry a failed buffered write when closing,
        # inadvertently triggering a second driver probe. One os.write call
        # issues just one bind request.
        fd = os.open(bind, os.O_WRONLY)
        try:
            n = os.write(fd, b'2-003c')
            if n != len(b'2-003c'):
                raise OSError(errno.EIO, 'short bind write')
        finally:
            os.close(fd)
        result.append('bind succeeded')
    except OSError as e:
        result.append(f'bind failed: errno {e.errno} ({errno.errorcode.get(e.errno, "UNKNOWN")}): {e.strerror}')
    after = time.monotonic() - start
    time.sleep(0.2)
finally:
    done.set()
    for thread in threads:
        thread.join()

print(f'Probe interval: {before:.4f}s to {after:.4f}s after sampling start')
print('Probe result:', result[0])
for when, kind, value in sorted(events):
    print(f'{when:.4f}s {kind}: {value}')
print(f'Samples: gpio={counts["gpio"]}, clock={counts["clock"]}')
print('Polling can miss brief states; values are software-reported, not electrical measurements.')
print('Camera driver now bound:', (device / 'driver').is_symlink())
