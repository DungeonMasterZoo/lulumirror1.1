import asyncio
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import AsyncMock, patch


path = Path(__file__).resolve().parents[1] / 'kiosk/services/events/presence.py'
spec = importlib.util.spec_from_file_location('event_presence', path)
presence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(presence)


class PresenceTests(unittest.TestCase):
    def test_countdown_motion_screen_off_and_wake(self):
        with tempfile.NamedTemporaryFile() as backlight:
            detector = presence.Presence(5, 20, .02, 100, backlight.name)
            detector.last_motion = 0
            still = bytes(presence.FRAME_SIZE)
            moved = bytes([255]) * presence.FRAME_SIZE
            self.assertFalse(detector.frame(still, 0))
            self.assertEqual(detector.event(1.1, False)['remainingSeconds'], 4)
            self.assertFalse(detector.frame(still, 5))
            off = detector.event(5, False)
            self.assertFalse(off['screenOn'])
            self.assertIsNone(off['remainingSeconds'])
            self.assertEqual(Path(backlight.name).read_text(), '0')
            self.assertTrue(detector.frame(moved, 6))
            on = detector.event(6, True)
            self.assertTrue(on['screenOn'])
            self.assertEqual(on['remainingSeconds'], 5)
            self.assertEqual(Path(backlight.name).read_text(), '100')

    def test_invalid_configuration_rejected(self):
        with patch.dict(os.environ, {'PRESENCE_TIMEOUT': 'nan'}):
            with self.assertRaises(ValueError):
                presence.configuration()


class PresenceReaderTests(unittest.IsolatedAsyncioTestCase):
    async def test_frame_eof_and_timeout_report_unavailable(self):
        class Bus:
            def __init__(self):
                self.events = asyncio.Queue()
            def publish(self, event, data):
                self.events.put_nowait((event, data))

        class Process:
            returncode = None
            def __init__(self, error):
                self.stdout = self
                self.error = error
            async def readexactly(self, size):
                raise self.error
            def terminate(self):
                self.returncode = 0
            async def wait(self):
                return 0

        for error in (asyncio.IncompleteReadError(b'', presence.FRAME_SIZE), asyncio.TimeoutError()):
            with self.subTest(error=type(error).__name__), tempfile.NamedTemporaryFile() as backlight:
                bus = Bus()
                with patch.object(presence.asyncio, 'create_subprocess_exec', new=AsyncMock(return_value=Process(error))):
                    task = asyncio.create_task(presence.presence_reader(bus, (5, 20, .02, 100, backlight.name)))
                    event, data = await asyncio.wait_for(bus.events.get(), 1)
                    self.assertEqual(event, 'presence')
                    self.assertFalse(data['available'])
                    self.assertEqual(Path(backlight.name).read_text(), '100')
                    task.cancel()
                    await asyncio.gather(task, return_exceptions=True)

    async def test_failure_reports_unavailable_and_restores_backlight(self):
        class Bus:
            def __init__(self):
                self.events = asyncio.Queue()
            def publish(self, event, data):
                self.events.put_nowait((event, data))

        with tempfile.NamedTemporaryFile() as backlight:
            Path(backlight.name).write_text('0')
            bus = Bus()
            with patch.object(presence.asyncio, 'create_subprocess_exec',
                              new=AsyncMock(side_effect=OSError('camera unavailable'))):
                task = asyncio.create_task(presence.presence_reader(bus, (5, 20, .02, 100, backlight.name)))
                event, data = await asyncio.wait_for(bus.events.get(), 1)
                self.assertEqual(event, 'presence')
                self.assertFalse(data['available'])
                self.assertEqual(Path(backlight.name).read_text(), '100')
                task.cancel()
                await asyncio.gather(task, return_exceptions=True)

    async def test_frames_are_published_and_exit_restores_backlight(self):
        class Bus:
            def __init__(self):
                self.events = asyncio.Queue()
            def publish(self, event, data):
                self.events.put_nowait((event, data))

        class Stream:
            async def readexactly(self, size):
                await asyncio.sleep(.01)
                return bytes(size)

        class Process:
            stdout = Stream()
            returncode = None
            def terminate(self):
                self.returncode = 0
            async def wait(self):
                return 0

        with tempfile.NamedTemporaryFile() as backlight:
            bus = Bus()
            with patch.object(presence.asyncio, 'create_subprocess_exec', new=AsyncMock(return_value=Process())):
                task = asyncio.create_task(presence.presence_reader(bus, (5, 20, .02, 100, backlight.name)))
                event, data = await asyncio.wait_for(bus.events.get(), 1)
                self.assertEqual(event, 'presence')
                self.assertTrue(data['available'])
                self.assertTrue(data['screenOn'])
                self.assertGreaterEqual(data['remainingSeconds'], 1)
                json.dumps(data, allow_nan=False)
                task.cancel()
                await asyncio.gather(task, return_exceptions=True)
                self.assertEqual(Path(backlight.name).read_text(), '100')
