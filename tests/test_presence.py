import importlib.util
import tempfile
import unittest
from pathlib import Path


spec = importlib.util.spec_from_file_location('presence', 'kiosk/services/events/presence.py')
presence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(presence)


class PresenceTests(unittest.TestCase):
    def test_screen_writes_and_state(self):
        with tempfile.NamedTemporaryFile() as backlight:
            detector = presence.Presence(120, 20, .02, 5, backlight.name)
            detector.set_screen(False)
            self.assertTrue(detector.screen_off)
            self.assertEqual(Path(backlight.name).read_text(), '0')
            detector.set_screen(True)
            self.assertFalse(detector.screen_off)
            self.assertEqual(Path(backlight.name).read_text(), '5')

    def test_motion_timeout_and_wake(self):
        with tempfile.NamedTemporaryFile() as backlight:
            detector = presence.Presence(120, 20, .02, 5, backlight.name)
            detector.last_motion = 0
            still = bytes(presence.FRAME_SIZE)
            moved = bytes([255]) * presence.FRAME_SIZE
            detector.frame(still, 0)
            detector.frame(still, 119)
            self.assertFalse(detector.screen_off)
            detector.frame(still, 120)
            self.assertTrue(detector.screen_off)
            detector.frame(moved, 121)
            self.assertFalse(detector.screen_off)
            self.assertEqual(detector.last_motion, 121)

if __name__ == '__main__':
    unittest.main()
