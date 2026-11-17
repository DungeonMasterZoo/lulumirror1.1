import asyncio
import importlib.util
import json
import math
import shutil
import subprocess
import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import AsyncMock, Mock, patch


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'kiosk/services/events'))
import button
import sound
spec = importlib.util.spec_from_file_location('kiosk_events', Path(sys.path[0]) / 'kiosk-events.py')
events = importlib.util.module_from_spec(spec)
spec.loader.exec_module(events)


class EventTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.bus = events.EventBus()
        self.server = await asyncio.start_server(
            lambda r, w: events.handle_client(r, w, self.bus), '127.0.0.1', 0)
        self.port = self.server.sockets[0].getsockname()[1]

    async def asyncTearDown(self):
        self.server.close()
        await self.server.wait_closed()

    async def request(self, origin=None):
        reader, writer = await asyncio.open_connection('127.0.0.1', self.port)
        origin_header = f'Origin: {origin}\r\n' if origin else ''
        writer.write(f'GET /v1/events HTTP/1.1\r\nHost: 127.0.0.1:{events.PORT}\r\n{origin_header}\r\n'.encode())
        await writer.drain()
        return reader, writer

    async def test_button_socket_to_sse(self):
        with tempfile.TemporaryDirectory() as directory:
            socket_path = str(Path(directory) / 'button.sock')
            connected = asyncio.Future()

            async def button_client(reader, writer):
                connected.set_result(writer)

            button_server = await asyncio.start_unix_server(button_client, socket_path)
            task = asyncio.create_task(button.button_reader(self.bus, socket_path))
            button_writer = await asyncio.wait_for(connected, 1)
            reader, writer = await self.request()
            self.assertIn(b'200 OK', await reader.readuntil(b'\r\n\r\n'))
            self.assertEqual(await reader.readuntil(b'\n\n'), b': connected\n\n')
            button_writer.write(b'ignored\ntap\n')
            await button_writer.drain()
            message = (await asyncio.wait_for(reader.readuntil(b'\n\n'), 1)).decode()
            self.assertTrue(message.startswith('event: button\n'))
            payload = json.loads(message.split('data: ', 1)[1])
            self.assertEqual(payload['action'], 'tap')
            self.assertEqual(payload['source'], 'button.bottom')
            self.assertEqual(payload['version'], 1)
            writer.close()
            button_writer.close()
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)
            button_server.close()
            await button_server.wait_closed()

    async def test_remote_origin_is_rejected(self):
        reader, writer = await self.request('https://example.com')
        self.assertIn(b'403 Forbidden', await reader.read())
        writer.close()
        await writer.wait_closed()

    async def test_disallowed_peer_rejected_before_reading(self):
        reader = AsyncMock()
        writer = Mock()
        writer.get_extra_info.return_value = ('10.0.75.241', 12345)
        writer.drain = AsyncMock()
        writer.wait_closed = AsyncMock()
        await events.handle_client(reader, writer, self.bus)
        self.assertIn(b'403 Forbidden', writer.write.call_args.args[0])
        reader.readuntil.assert_not_awaited()
        writer.close.assert_called_once()

    async def test_allowed_lan_peer_and_host(self):
        reader = AsyncMock()
        reader.readuntil.return_value = (
            f'GET /v1/events HTTP/1.1\r\nHost: 10.0.76.64:{events.PORT}\r\n\r\n'.encode())
        reader.read.return_value = b''
        writer = Mock()
        writer.get_extra_info.return_value = ('10.0.75.240', 12345)
        writer.drain = AsyncMock()
        writer.wait_closed = AsyncMock()
        await events.handle_client(reader, writer, self.bus)
        self.assertIn(b'200 OK', writer.write.call_args_list[0].args[0])
        self.assertFalse(self.bus.clients)

    async def test_allowed_origin_receives_cors_and_events(self):
        reader, writer = await self.request('https://mywebsite.com')
        headers = await reader.readuntil(b'\r\n\r\n')
        self.assertIn(b'200 OK', headers)
        self.assertIn(b'Access-Control-Allow-Origin: https://mywebsite.com\r\n', headers)
        await reader.readuntil(b'\n\n')
        self.bus.publish('button', {'action': 'tap'})
        self.assertIn(b'"action":"tap"', await asyncio.wait_for(reader.readuntil(b'\n\n'), 1))
        writer.close()
        await writer.wait_closed()

    async def test_button_reader_reconnects(self):
        with tempfile.TemporaryDirectory() as directory:
            socket_path = str(Path(directory) / 'button.sock')
            connections = asyncio.Queue()

            async def button_client(reader, writer):
                await connections.put(writer)

            server = await asyncio.start_unix_server(button_client, socket_path)
            task = asyncio.create_task(button.button_reader(self.bus, socket_path))
            first = await asyncio.wait_for(connections.get(), 1)
            first.close()
            await first.wait_closed()
            second = await asyncio.wait_for(connections.get(), 3)
            queue = asyncio.Queue()
            self.bus.clients.add(queue)
            second.write(b'double\n')
            await second.drain()
            self.assertIn(b'"action":"double"', await asyncio.wait_for(queue.get(), 1))
            second.close()
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)
            server.close()
            await server.wait_closed()

    async def test_slow_consumer_is_disconnected(self):
        queue = asyncio.Queue(maxsize=1)
        self.bus.clients.add(queue)
        self.bus.publish('button', {'action': 'tap'})
        self.bus.publish('button', {'action': 'hold'})
        self.assertIsNone(queue.get_nowait())
        self.assertNotIn(queue, self.bus.clients)

    async def test_sound_fanout_and_live_only(self):
        clients = [await self.request('https://mywebsite.com') for _ in range(2)]
        for reader, _ in clients:
            await reader.readuntil(b'\r\n\r\n')
            await reader.readuntil(b'\n\n')
        sound.sound_event(self.bus, True, {'estimatedDba': 72.4, 'dbfs': -29, 'warning': False})
        messages = [await asyncio.wait_for(r.readuntil(b'\n\n'), 1) for r, _ in clients]
        self.assertEqual(messages[0], messages[1])
        self.assertTrue(messages[0].startswith(b'event: sound\n'))
        self.assertTrue(json.loads(messages[0].split(b'data: ')[1])['available'])
        for _, writer in clients:
            writer.close()
            await writer.wait_closed()

    async def test_presence_sse_fanout(self):
        clients = [await self.request('https://mywebsite.com') for _ in range(2)]
        for reader, _ in clients:
            await reader.readuntil(b'\r\n\r\n')
            await reader.readuntil(b'\n\n')
        self.bus.publish('presence', {'version': 1, 'source': 'camera.motion', 'available': True,
                                      'screenOn': True, 'motion': False, 'timeoutSeconds': 300,
                                      'remainingSeconds': 240})
        messages = [await asyncio.wait_for(reader.readuntil(b'\n\n'), 1) for reader, _ in clients]
        self.assertEqual(messages[0], messages[1])
        self.assertTrue(messages[0].startswith(b'event: presence\n'))
        self.assertEqual(json.loads(messages[0].split(b'data: ')[1])['remainingSeconds'], 240)
        for _, writer in clients:
            writer.close()
            await writer.wait_closed()

    async def test_capture_failure_then_recovery(self):
        queue = asyncio.Queue()
        self.bus.clients.add(queue)
        calls = 0

        async def availability():
            nonlocal calls
            calls += 1
            return calls > 1

        class Stream:
            async def readexactly(self, n):
                await asyncio.sleep(0.01)
                return b'\x00' * n

        class Process:
            stdout = Stream()
            returncode = None
            def terminate(self):
                self.returncode = 0
            async def wait(self):
                return 0

        monitor = sound.AudioMonitor()
        monitor.microphone_available = AsyncMock(side_effect=availability)
        with patch.object(sound.asyncio, 'create_subprocess_exec', new=AsyncMock(return_value=Process())):
            task = asyncio.create_task(sound.sound_reader(self.bus, monitor))
            unavailable = json.loads((await asyncio.wait_for(queue.get(), 1)).split(b'data: ')[1])
            self.assertFalse(unavailable['available'])
            available = json.loads((await asyncio.wait_for(queue.get(), 3)).split(b'data: ')[1])
            self.assertTrue(available['available'])
            self.assertFalse(available['warning'])
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)

    async def test_microphone_mute_and_source_check(self):
        monitor = sound.AudioMonitor()
        good = {'available': True, 'volume': 1.0, 'muted': False}
        now = sound.time.monotonic()
        monitor.update({'available': True, 'volume': 1.0, 'muted': True}, True, now)
        self.assertFalse(await monitor.microphone_available())
        monitor.update(good, True, now)
        self.assertTrue(await monitor.microphone_available())
        monitor.update(good, False, now)
        self.assertFalse(await monitor.microphone_available())
        monitor.update(good, True, now - sound.AUDIO_STATUS_MAX_AGE - 1)
        self.assertFalse(await monitor.microphone_available())
        monitor.update({'available': False}, True, now)
        self.assertFalse(await monitor.microphone_available())
        with patch.object(sound, 'run_command', new=AsyncMock(return_value='node.name = "other"')):
            self.assertFalse(await sound.default_source_is_microphone())
        with patch.object(sound, 'run_command', new=AsyncMock(side_effect=OSError('down'))):
            self.assertFalse(await sound.default_source_is_microphone())

    async def test_microphone_state_is_queried_once_per_poll_and_shared(self):
        monitor = sound.AudioMonitor()
        response = AsyncMock(side_effect=['Volume: 1.00', 'Volume: 0.40',
                                          '* node.name = "mirror-microphone"'])
        with patch.object(sound, 'run_command', new=response):
            task = asyncio.create_task(sound.audio_state_reader(self.bus, monitor))
            await asyncio.wait_for(monitor.ready.wait(), 1)
            self.assertTrue(await monitor.microphone_available())
            self.assertEqual(response.await_count, 3)
            self.assertEqual(sum(call.args == ('wpctl', 'get-volume', '@DEFAULT_AUDIO_SOURCE@')
                                 for call in response.await_args_list), 1)
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)

    async def test_audio_device_state(self):
        cases = [
            ('Volume: 1.00', {'available': True, 'volume': 1.0, 'muted': False}),
            ('Volume: 0.40 [MUTED]', {'available': True, 'volume': 0.4, 'muted': True}),
            ('Volume: 0.00', {'available': True, 'volume': 0.0, 'muted': False}),
            ('Volume: 1.50', {'available': True, 'volume': 1.5, 'muted': False}),
            ('Volume: nan', {'available': False}),
            ('Volume: -0.1', {'available': False}),
            ('unexpected', {'available': False}),
        ]
        for output, expected in cases:
            with self.subTest(output=output), patch.object(sound, 'run_command', new=AsyncMock(return_value=output)):
                self.assertEqual(await sound.audio_device_state('@DEFAULT_AUDIO_SOURCE@'), expected)
        with patch.object(sound, 'run_command', new=AsyncMock(side_effect=OSError('unavailable'))):
            self.assertEqual(await sound.audio_device_state('@DEFAULT_AUDIO_SINK@'), {'available': False})

    async def test_audio_state_fanout_and_refresh(self):
        clients = [await self.request('https://mywebsite.com') for _ in range(2)]
        for reader, _ in clients:
            await reader.readuntil(b'\r\n\r\n')
            await reader.readuntil(b'\n\n')
        publisher = sound.AudioStatePublisher(self.bus)
        mic = {'available': True, 'volume': 1.0, 'muted': False}
        speaker = {'available': True, 'volume': 0.4, 'muted': False}
        publisher.update(mic, speaker, 0)
        messages = [await asyncio.wait_for(reader.readuntil(b'\n\n'), 1) for reader, _ in clients]
        self.assertEqual(messages[0], messages[1])
        self.assertTrue(messages[0].startswith(b'event: audio.state\n'))
        payload = json.loads(messages[0].split(b'data: ')[1])
        self.assertEqual(payload['microphone'], mic)
        self.assertEqual(payload['speaker'], speaker)
        publisher.update(mic, speaker, 1)
        self.assertTrue(all(queue.empty() for queue in self.bus.clients))
        publisher.update(mic, {'available': False}, 2)
        for reader, _ in clients:
            message = await asyncio.wait_for(reader.readuntil(b'\n\n'), 1)
            self.assertEqual(json.loads(message.split(b'data: ')[1])['speaker'], {'available': False})
        publisher.update(mic, {'available': False}, 7)
        for reader, writer in clients:
            self.assertIn(b'event: audio.state', await asyncio.wait_for(reader.readuntil(b'\n\n'), 1))
            writer.close()
            await writer.wait_closed()

    async def test_audio_state_new_client_gets_next_live_refresh(self):
        publisher = sound.AudioStatePublisher(self.bus)
        state = {'available': False}
        publisher.update(state, state, 0)
        reader, writer = await self.request()
        await reader.readuntil(b'\r\n\r\n')
        await reader.readuntil(b'\n\n')
        self.assertTrue(next(iter(self.bus.clients)).empty())
        publisher.update(state, state, 5)
        self.assertIn(b'event: audio.state', await asyncio.wait_for(reader.readuntil(b'\n\n'), 1))
        writer.close()
        await writer.wait_closed()


class MeterTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('node'), 'Node.js needed for browser-equivalent comparison')
    def test_matches_browser_filter_math(self):
        script = r'''
const fs = 48000, w = 2 * Math.PI * 1000 / fs;
let gain = 1, stages = [];
for (const [type, f] of [['high',20.598997],['high',20.598997],['high',107.65265],['high',737.86223],['low',12194.217],['low',12194.217]]) {
  const k = Math.PI * f / fs, b0 = (type === 'high' ? 1 : k) / (1 + k);
  const b1 = type === 'high' ? -b0 : b0, a1 = (k - 1) / (k + 1);
  gain *= Math.hypot(b0 + b1 * Math.cos(w), b1 * Math.sin(w)) / Math.hypot(1 + a1 * Math.cos(w), a1 * Math.sin(w));
  stages.push({b0,b1,a1,x:0,y:0});
}
let raw = [], filtered = [];
for (let i=0; i<24000; i++) {
  let x = 0.12 * Math.sin(2*Math.PI*300*i/fs) + 0.04 * Math.cos(2*Math.PI*5000*i/fs);
  raw.push(x);
  for (const s of stages) { const y=s.b0*x+s.b1*s.x-s.a1*s.y; s.x=x; s.y=y; x=y; }
  filtered.push(x/gain);
}
const db = xs => 20 * Math.log10(Math.max(Math.sqrt(xs.slice(-2048).reduce((a,x)=>a+x*x,0)/2048),0.00001));
console.log(JSON.stringify({estimatedDba:db(filtered)+100.9,dbfs:Math.round(db(raw))}));
'''
        expected = json.loads(subprocess.check_output(['node', '-e', script], text=True))
        meter = sound.SoundMeter()
        meter.feed([0.12 * math.sin(2 * math.pi * 300 * i / 48000) +
                    0.04 * math.cos(2 * math.pi * 5000 * i / 48000) for i in range(24000)])
        actual = meter.reading(0)
        self.assertAlmostEqual(actual['estimatedDba'], expected['estimatedDba'], places=8)
        self.assertEqual(actual['dbfs'], expected['dbfs'])

    def test_rms_floor_and_rounding(self):
        meter = sound.SoundMeter()
        meter.feed([0.0] * 2048)
        self.assertEqual(meter.reading(0)['dbfs'], -100)
        self.assertAlmostEqual(meter.reading(0)['estimatedDba'], 0.9)
        self.assertAlmostEqual(sound.SoundMeter.db([0.5] * 2048), -6.020599913, places=8)
        meter = sound.SoundMeter()
        meter.feed([10 ** (-29.5 / 20)] * 2048)
        self.assertEqual(meter.reading(0)['dbfs'], -29)

    def test_filter_normalization_and_buffer_continuity(self):
        samples = [0.2 * math.sin(2 * math.pi * 1000 * i / 48000) for i in range(48000)]
        whole, split = sound.SoundMeter(), sound.SoundMeter()
        whole.feed(samples)
        for i in range(0, len(samples), 333):
            split.feed(samples[i:i + 333])
        self.assertEqual(list(whole.weighted), list(split.weighted))
        self.assertAlmostEqual(whole.db(whole.raw), whole.db(whole.weighted), delta=0.05)
        with self.assertRaises(ValueError):
            sound.SoundMeter(24000)

    def test_hysteresis_boundaries_and_reset(self):
        meter = sound.SoundMeter()
        for value, now in [(80, 0), (79.99, 1), (80, 2), (80, 3.99)]:
            meter.update_warning(value, now)
            self.assertFalse(meter.warning)
        meter.update_warning(80, 4)
        self.assertTrue(meter.warning)
        for value, now in [(74.99, 5), (75, 6), (74.99, 7), (74.99, 9.99)]:
            meter.update_warning(value, now)
            self.assertTrue(meter.warning)
        meter.update_warning(74.99, 10)
        self.assertFalse(meter.warning)


if __name__ == '__main__':
    unittest.main()
