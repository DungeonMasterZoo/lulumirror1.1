# MIRROR GUI and kiosk

## Current status

The kiosk now opens `https://mywebsite.com/mirrors/1`. Its Chromium
command no longer uses the broad fake media-permission or autoplay flags. The
deployed [`kiosk-chromium-policy.json`](../kiosk/services/display/kiosk-chromium-policy.json)
policy allows camera, microphone, autoplay, and loopback access for the
`https://mywebsite.com` origin. The unit and policy were installed and the
kiosk restarted; policy behavior and media playback still need on-device
verification. Other origin requests no longer receive these automatic grants.

LemonadeMirror is running Debian 13 on the MIRROR. Cage and Chromium are installed. The persistent kiosk service is installed and enabled, and the user previously confirmed that it worked after a reboot with <https://lululemon.com>.

The user previously confirmed the test YouTube page at <https://www.youtube.com/watch?v=WNCl-69POro> appeared, but it did not initially autoplay. Adding `autoplay=1` to the test URL and passing Chromium `--autoplay-policy=no-user-gesture-required` enabled playback; the user confirmed video and audio. That broad flag has since been removed in favor of the origin-scoped policy above.

The connected `LVDS-1` display reports a 1920x1080 mode and is rotated 90 degrees for the mirror. The user confirmed the rotation works. The updated service was installed and restarted over SSH; `wlr-randr` reported `Transform: 90`. The rotation-enabled service has not yet been tested after a reboot.

When the screen appeared blank, its backlight brightness and actual brightness were both 0. The existing `screen-off.service` is configured to set the backlight to 0 at boot, and `systemd-backlight@backlight:backlight.service` is masked. The backlight was manually set to 50 and then 100 out of 100 during initial testing; the current kiosk service sets it to 5 after `screen-off.service`.

## Persistent kiosk service

The repository copy is [`kiosk/services/display/kiosk.service`](../kiosk/services/display/kiosk.service); it is installed at `/etc/systemd/system/kiosk.service` on the MIRROR. It runs Cage and Chromium as `mirror` on tty2, switches to that terminal, sets brightness to 5, and restarts on failure. It is enabled under `graphical.target` and ordered after `screen-off.service`. It requests `network-online.target`, although that target alone does not guarantee the website is reachable.

The unit was checked with `systemd-analyze verify`, enabled and started. Its active state, browser processes, and brightness were checked over SSH, and the user subsequently confirmed that the original website worked after reboot. After the YouTube test, the original URL was restored and the service restarted; this latest configuration has not been tested after reboot. The earlier temporary service was stopped. The existing screen-off service was not modified.

```sh
sudo systemctl status kiosk.service --no-pager
sudo journalctl -u kiosk.service -b --no-pager
sudo systemctl restart kiosk.service
sudo systemctl disable --now kiosk.service
```

If the repository copy is changed, copy it to `/etc/systemd/system/kiosk.service`, then run `sudo systemctl daemon-reload` and restart the service. Disabling the kiosk does not uninstall packages or change the existing boot-time screen-off setting.

## Display rotation

The service starts a shell as Cage's application. Once Cage has established its Wayland session, that shell runs `wlr-randr --output LVDS-1 --transform 90` in the background and starts Chromium. This reapplies the rotation whenever Cage starts. Rotation is configured within Cage's session rather than in Chromium; the installed Cage version does not support the older `-r` option.

A separate `ExecStartPost` rotation command was tried, but its separate PAM login session was followed by Cage losing display access. Running the command inside Cage's session avoids that observed failure. A rotation error is logged but does not prevent Chromium from starting.

To inspect or adjust the running session over SSH as `mirror`:

```sh
export XDG_RUNTIME_DIR=/run/user/1000
export WAYLAND_DISPLAY=wayland-0
wlr-randr
wlr-randr --output LVDS-1 --transform 90
```

Use `270` for the opposite direction or `normal` to undo the rotation. Manual changes apply only to the running session; edit the service and reinstall it to change the startup setting. The socket name shown here was verified on this device, but may differ in another session.

## Temporary camera preview

The kiosk currently opens `/home/mirror/kiosk-camera-test.html`, installed from [`kiosk/services/display/index.html`](../kiosk/services/display/index.html), instead of the website. It is testing native Chromium capture via `getUserMedia`. Chromium is temporarily started with `--use-fake-ui-for-media-stream`, which automatically grants camera and microphone requests to pages in this session; remove it before normal browsing. The hub currently runs [`kiosk/camera/camhub-byte-swap-test.sh`](../kiosk/camera/camhub-byte-swap-test.sh), using [`kiosk/camera/uyvy-swap-stream.c`](../kiosk/camera/uyvy-swap-stream.c) compiled to `/home/mirror/uyvy-swap-stream` to provide a 1920x1080 YUYV feed. A rotation test using [`kiosk/camera/camhub-rotate-test.sh`](../kiosk/camera/camhub-rotate-test.sh) and [`kiosk/camera/uyvy-rotate-stream.c`](../kiosk/camera/uyvy-rotate-stream.c) looked correct but was slow, and the byte-swap-only feed was restored. These experiments affect all shared-feed consumers. The original hub script is backed up at `/usr/local/sbin/camhub.sh.pre-rotation`; the previous FFmpeg-conversion test is at `/usr/local/sbin/camhub.sh.yuyv-conversion`, the direct-YUYV test at `/usr/local/sbin/camhub.sh.pre-byte-swap-test`, and the byte-swap-only test at `/usr/local/sbin/camhub.sh.pre-rotate-stream-test`.

Repository copies of the preceding direct-YUYV test and the pre-experiment hub script are in [`kiosk/camera/camhub.sh`](../kiosk/camera/camhub.sh) and [`kiosk/camera/camhub.ov564[05].sh`](../kiosk/camera/camhub.ov564[05].sh), respectively. The backup's equivalence to the upstream LemonadeLinux version has not been verified. The direct-YUYV script retains its original header comment, which describes the old UYVY feed.

The JPEG preview bridge ([`kiosk/services/preview/mirror-camera-preview.service`](../kiosk/services/preview/mirror-camera-preview.service) and [`kiosk/services/preview/camera-preview.py`](../kiosk/services/preview/camera-preview.py)) is running alongside the native Chromium test at `http://10.0.76.64:8765/camera`. It reads the current 1920x1080, 30 fps YUYV shared feed without an explicit resize or frame-rate limit, encoding JPEG for browsers; actual throughput depends on available resources. Viewers share one on-demand encoder, which stops after the last client disconnects. It was started manually, not enabled at boot. It listens on all IPv4 interfaces with no authentication or encryption. It does not record video. Stop it with `sudo systemctl stop mirror-camera-preview.service` when it is no longer needed. To return to the website and original camera format, restore the backed-up hub script, change the kiosk service URL back to `https://lululemon.com`, adjust its camera dependency as needed, reinstall and restart the services.

## Experimental motion presence service

[`kiosk/services/events/presence.py`](../kiosk/services/events/presence.py) implements motion-based backlight control in the deployed combined event service. The legacy standalone presence service has been stopped, disabled, and removed from the mirror. The combined service publishes live presence events; its screen-off and wake-up behavior still needs on-device verification. Both versions use the shared `/dev/video10` feed, sample one blurred 320x180 grayscale frame per second, turn the backlight off after 300 seconds without detected motion, and wake it on motion. They do not detect faces or gaze, record images, or need image rotation. Someone sitting still may time out; lighting changes can trigger motion. A frozen feed that continues delivering identical frames cannot be reliably distinguished from a still scene.

The service expects the current 1920x1080 YUYV 30 fps shared feed, `/usr/bin/ffmpeg`, Python 3, and the backlight path used by the kiosk. It runs as root to access the backlight. When capture ends or stalls, the service restores brightness to 100 and retries; systemd also restores it when the process exits. Neither mechanism can guarantee recovery from a system-wide failure. The kiosk also writes brightness at startup, so a kiosk restart can turn the backlight on independently of presence control.

See [`kiosk/services/events/README.md`](../kiosk/services/events/README.md) for migration precautions and presence settings. The cleanup command uses the default backlight path; if changing `PRESENCE_BACKLIGHT`, also change `ExecStopPost` to match. Test detection, wake-up, camera failure, and CPU load on the device before relying on it.

## Installation

Connected over SSH as `mirror` to `10.0.76.64`, refreshed the existing Debian package indexes, and installed the Debian packages with:

```sh
sudo apt-get update
sudo apt-get install -y --no-install-recommends cage chromium
sudo apt-get install -y --no-install-recommends kbd
sudo apt-get install -y wlr-randr
```

`kbd` supplies `chvt`, used to switch to the kiosk's virtual terminal; `wlr-randr` configures the display rotation. Installing Cage and Chromium also installed their dependencies and upgraded `zlib1g`. At the time of installation, the root filesystem had about 4.2 GB free and the device had about 1.9 GiB of RAM.

## Temporary display test

The first transient systemd unit, `mirror-kiosk-test`, did not start Chromium. It was stopped and forcibly terminated after it became stuck during shutdown. A second transient unit was launched on virtual terminal 2 after switching to that terminal:

```sh
sudo chvt 2
sudo systemd-run --unit=mirror-kiosk-try2 \
  --property=User=mirror \
  --property=PAMName=login \
  --property=TTYPath=/dev/tty2 \
  --property=StandardInput=tty \
  --property=StandardOutput=journal \
  --property=StandardError=journal \
  --setenv=XDG_RUNTIME_DIR=/run/user/1000 \
  /usr/bin/cage -- /usr/bin/chromium \
  --ozone-platform=wayland --kiosk --no-first-run \
  --disable-session-crashed-bubble https://lululemon.com
```

The session runs as the `mirror` user, not root. This is an experimental, transient unit, not a tested boot configuration. Starting the processes does not by itself prove that the page loaded or that the display is visible.

Useful checks:

```sh
systemctl status mirror-kiosk-try2 --no-pager
sudo journalctl -u mirror-kiosk-try2 --no-pager
cat /sys/class/tty/tty0/active
cat /sys/class/drm/card0-LVDS-1/status
cat /sys/class/backlight/backlight/{brightness,actual_brightness,max_brightness}
```

The installed LemonadeMirror helper was used to turn the backlight on for the test:

```sh
sudo screenon 100
```

`sudo screenoff` sets brightness back to 0. The boot-time screen-off service has not been changed. The persistent kiosk is ordered after it, and the user confirmed that the kiosk works after reboot.
