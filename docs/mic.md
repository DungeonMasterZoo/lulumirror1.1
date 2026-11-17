# Mirror microphone

## Current setup

The mirror's digital microphone appears in ALSA as `tas5806-audio`, capture device `hw:0,1`. The existing `/etc/asound.conf` defines the ALSA `mic` device, which routes capture through `mirror_mic` and `mirror_dsnoop` to that hardware. The existing ALSA configuration was not changed.

Chromium initially reported that the requested microphone device was not found. ALSA could see the hardware, but PipeWire did not expose an audio input. A PipeWire drop-in, [`kiosk/audio/pipewire-microphone.conf`](../kiosk/audio/pipewire-microphone.conf), was installed at `/home/mirror/.config/pipewire/pipewire.conf.d/mirror-microphone.conf`. It creates an `Audio/Source` named `mirror-microphone` using the existing ALSA `mic` device. PipeWire loads `.conf` drop-ins alongside its main configuration.

The PipeWire, PipeWire PulseAudio, and WirePlumber user services were restarted. The new source was selected as the default with `wpctl set-default`, and the kiosk was restarted. Afterward, `wpctl status` showed `Mirror Microphone` as the default source and Chromium's input stream connected to it. This confirms the connection, not that the microphone produces a useful signal or that the warning threshold is calibrated. Persistence of the default selection across reboot has not been verified.

## Kiosk sound meter

[`kiosk/services/display/index.html`](../kiosk/services/display/index.html) requests microphone access separately from the camera and displays both unweighted digital RMS level in dBFS and an estimated dBA calculated from an A-weighted signal. The filter approximates the A-weighting curve and is normalized at 1 kHz. The offset is 100.9 dB: an initial comparison set it to 110.9 dB, then it was reduced by 10 dB after the NIOSH iPhone app read 10 dB less than the mirror. The estimate is green below 60, yellow from 60, orange from 70, and red from 80 estimated dBA. A separate warning appears after the estimate stays at or above 80 dBA for two seconds and clears after three seconds below 75 dBA. These colors are illustrative, not safety limits. The offset and thresholds are in `startSoundMeter()` and may need adjustment for the microphone and room. This is not a hearing-safety meter.

Audio is processed locally in the browser and is not recorded by this page. The current kiosk launches Chromium with `--use-fake-ui-for-media-stream`, which automatically grants camera and microphone requests for pages opened in that session. See [gui.md](gui.md) for the kiosk setup and the implications of that temporary flag.

The display and warning logic update once per second using a short audio snapshot, not a full one-second average. Brief sounds between updates may be missed, and this is not equivalent to a sound meter's Slow time weighting.

## Inspecting and reinstalling

As the `mirror` user, with its user runtime available:

```sh
export XDG_RUNTIME_DIR=/run/user/1000
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
arecord -l
wpctl status
```

To reinstall the drop-in from the repository and restart the audio services:

```sh
install -d ~/.config/pipewire/pipewire.conf.d
install -m 644 kiosk/audio/pipewire-microphone.conf ~/.config/pipewire/pipewire.conf.d/mirror-microphone.conf
systemctl --user restart pipewire.service pipewire-pulse.service wireplumber.service
wpctl status
```

If necessary, select the `Mirror Microphone` source using its current numeric ID from `wpctl status`: `wpctl set-default ID`. IDs can change between sessions. Restart the kiosk with `sudo systemctl restart kiosk.service` to make Chromium request the microphone again. Restarting audio services can briefly interrupt audio.

The kiosk service opens `/home/mirror/kiosk-camera-test.html`, a separate installed copy of `kiosk/services/display/index.html`. Changes to the repository page must be copied there and the kiosk restarted before they appear on the mirror. See [gui.md](gui.md) for details.
