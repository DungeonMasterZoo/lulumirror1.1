import asyncio
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import AsyncMock, patch


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'kiosk/services/events'))
import bluetooth
import wifi


class WifiTests(unittest.IsolatedAsyncioTestCase):
    async def test_connected_escaped_ssid_and_no_scan(self):
        responses = ['enabled\n', 'wlan0:wifi:connected\n',
                     r'*:My\: network\\name:74' + '\n', '10.0.0.5/24\n']
        with patch.object(wifi, 'query', new=AsyncMock(side_effect=responses)) as query:
            result = await wifi.read_wifi()
        self.assertEqual(result, {'available': True, 'enabled': True, 'connected': True,
                                  'ssid': 'My: network\\name', 'signalPercent': 74, 'ipv4': '10.0.0.5'})
        self.assertIn('--rescan', query.call_args_list[2].args)
        self.assertIn('no', query.call_args_list[2].args)

    async def test_disabled_and_disconnected_do_not_scan(self):
        with patch.object(wifi, 'query', new=AsyncMock(side_effect=['disabled\n', 'wlan0:wifi:unavailable\n'])) as query:
            state = await wifi.read_wifi()
        self.assertEqual(query.await_count, 2)
        self.assertEqual(state, {'available': True, 'enabled': False, 'connected': False,
                                 'ssid': None, 'signalPercent': None, 'ipv4': None})

    async def test_errors_and_missing_devices_are_unavailable(self):
        with patch.object(wifi, 'query', new=AsyncMock(side_effect=OSError('down'))):
            self.assertEqual(await wifi.read_wifi(), {'available': False})
        with patch.object(wifi, 'query', new=AsyncMock(side_effect=['enabled', 'lo:loopback:connected'])):
            self.assertEqual(await wifi.read_wifi(), {'available': False})


class BluetoothTests(unittest.IsolatedAsyncioTestCase):
    async def test_connected_devices_and_address_redaction(self):
        controller = 'Controller AA:BB:CC:DD:EE:FF\n\tPowered: yes\n\tDiscoverable: no\n\tPairable: yes\n'
        devices = 'Device 11:22:33:44:55:66 Headphones\nDevice 22:33:44:55:66:77 22:33:44:55:66:77\n'
        with patch.object(bluetooth, 'query', new=AsyncMock(side_effect=[controller, devices])) as query:
            state = await bluetooth.read_bluetooth()
        self.assertTrue(state['enabled'])
        self.assertFalse(state['discoverable'])
        self.assertTrue(state['pairable'])
        self.assertEqual(state['connectedDevices'], [{'name': 'Headphones', 'connected': True},
                                                     {'name': 'Unknown device', 'connected': True}])
        self.assertNotIn('22:33:44:55:66:77', json.dumps(state))
        self.assertEqual(query.call_args_list[1].args, ('devices', 'Connected'))

    async def test_controller_failure_is_unavailable(self):
        with patch.object(bluetooth, 'query', new=AsyncMock(return_value='No default controller available')):
            self.assertEqual(await bluetooth.read_bluetooth(), {'available': False})
        with patch.object(bluetooth, 'query', new=AsyncMock(side_effect=asyncio.TimeoutError())):
            self.assertEqual(await bluetooth.read_bluetooth(), {'available': False})


class NetworkReaderTests(unittest.IsolatedAsyncioTestCase):
    async def test_readers_publish_and_recover(self):
        class Bus:
            def __init__(self):
                self.events = asyncio.Queue()
            def publish(self, kind, payload):
                self.events.put_nowait((kind, payload))

        for module, reader, event in [(wifi, wifi.wifi_reader, 'wifi'),
                                      (bluetooth, bluetooth.bluetooth_reader, 'bluetooth')]:
            with self.subTest(event=event):
                bus = Bus()
                state_reader = 'read_wifi' if event == 'wifi' else 'read_bluetooth'
                with patch.object(module, state_reader, new=AsyncMock(side_effect=[{'available': False}, {'available': True}])), \
                        patch.object(module, 'POLL_SECONDS', 0.01):
                    task = asyncio.create_task(reader(bus))
                    first = await asyncio.wait_for(bus.events.get(), 1)
                    second = await asyncio.wait_for(bus.events.get(), 1)
                    self.assertEqual(first[0], event)
                    self.assertFalse(first[1]['available'])
                    self.assertTrue(second[1]['available'])
                    self.assertEqual(second[1]['source'], event)
                    self.assertEqual(second[1]['version'], 1)
                    task.cancel()
                    await asyncio.gather(task, return_exceptions=True)


if __name__ == '__main__':
    unittest.main()
