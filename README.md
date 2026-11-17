# Repurposing a Lululemon MIRROR

This is a journal of my experience getting [LemonadeMirror](https://github.com/ikiiftekhar2/lemonademirror), a Debian-based system, running on my MIRROR's original NXP i.MX8M Mini board. It covers USB boot, backups, camera troubleshooting, and my Chromium kiosk setup, including the experiments and dead ends along the way. Some steps and fixes are specific to my unit, so you may not need all of them for yours.

Point your AI agent at this repository for context on what I tried, what worked, and the dead ends I ran into. It should give your agent a head start getting your own MIRROR up and running, but make sure it checks your hardware and verifies each step rather than assuming your unit is identical to mine.

## Project status

On this unit, USB boot access was achieved without JTAG or UART, the eMMC user area was backed up, and LemonadeMirror was installed and booted with SSH access. Camera investigation identified an OV5645 sensor; the camera configuration and subsequent kiosk work are documented below. Individual research entries describe the status at the time they were written and may contain earlier, superseded conclusions.

**My unit:** Model `M1.1-10090080`, FCC ID `VPYLBEE5HY1MW`, board marked `Mirror V1.1 EVT rev A08` (NXP i.MX8M Mini).

**My backups:** The verified stock Android eMMC user-area image is stored on my Mac at `~/Downloads/mirror-backup/mirror-user-area.img`. A separate copy of the original LemonadeMirror device tree is at `~/Downloads/mirror-backup/lemonademirror-original.dtb`. The user-area image does not include the eMMC boot0, boot1, or RPMB hardware partitions, and restoration has not been verified end to end. These local files are not included in this repository.

### Hardware check

The following is a recorded check from my unit; results may differ on yours:

```text
mirror@mirror:~$ sudo mirror-hwcheck
PASS  device tree                  lululemon Mirror V1.1
PASS  eMMC
PASS  display connector            connected
PASS  bridge PLL locked            0a=85
PASS  framebuffer
PASS  backlight                    brightness 0
PASS  camera                       /dev/video10, 15 frames
PASS  speakers
PASS  microphone
PASS  firmware tas5805m_dsp_tweeters.bin
PASS  firmware tas5805m_dsp_woofers.bin
PASS  firmware brcmfmac43455-sdio.bin
PASS  firmware BCM4345C0.hcd
PASS  Wi-Fi                        wlan0 up
PASS  Bluetooth
PASS  button driver                polling
PASS  button events
PASS  reboot fix
PASS  camera service
PASS  ssh

20 of 20 passed
Not checked here, needs a person: picture on the glass, sound by ear, button presses, phone pairing.
```

**Safety:** These experiments can make persistent changes or expose a writable disk. Flashing or changing boot settings can destroy data or leave a device unbootable. Disconnect mains power before working on the exposed board, verify your own hardware and disk identity, and keep a verified backup before writing. Reference images are not a backup of your device.

## TL;DR: From stock MIRROR to LemonadeMirror

- **Important:** These commands document our Apple Silicon Mac and one i.MX8M Mini MIRROR, not a universal installer. The disk checks contain **our device's partition GUIDs**, and the RAM boot tasks require locally built, hash-pinned files that are not included in this repository. They may stop on another device or fresh checkout. Do not bypass checks or reuse our offsets without independently verifying your hardware. See [boot-chain research](docs/boot-research.md) for the required reference files and builds.
- **Install prerequisites**, from the repository root after installing [mise](https://mise.jdx.dev/getting-started.html) and Apple's command-line tools: `mise trust`, `mise install`, then `mise run setup`. Download the pinned release with `mise run lemonade-download`. Follow the [downloads and preparation checklist](docs/downloads.md) for reference images, source checkouts and build limitations.
- **Enter download mode:** Disconnect mains power, connect the two `PROG1` pads and micro-USB, then power on. Run `mise run usb`; `MX8MM SDP` should appear immediately after power-on when the pads are electrically connected. If it does not, power off and disconnect mains before checking the contacts. The pads may have solder mask, conformal coating, or oxidation that prevents contact. If a coating covers the contact points, carefully remove only enough to expose the pads. Make the connection again with power disconnected and retry; do not scrape or reposition probes on a powered board. Also check the USB **data** cable and connection if detection still fails.

  For convenience, I used this loop to watch for the device. Stop it with `Ctrl+C`:

  ```sh
  while true; do
    date '+%H:%M:%S'
    mise run usb
    sleep 1
  done
  ```

- **Expose storage:** First run `mise run ums-direct-boot -- --check`; only if its required local files and compatibility are verified, run `mise run ums-direct-boot`. Run `diskutil list` and independently identify the newly exposed MIRROR whole disk. It is **writable**; if macOS offers to initialize it, choose **Ignore**.
- **Back up:** Replace `diskN` in every command below with the independently verified MIRROR disk, never an example number. Unmount its volumes with `diskutil unmountDisk /dev/diskN`, then run `mise run backup-copy -- diskN`. This backs up only the user area, not boot0, boot1 or RPMB; restoration has not been verified end to end.
- **Test persistent USB boot:** Power-cycle back into SDP, run `mise run probe-reference-boot0`, and review the comparison and partition selection. Power-cycle into SDP again, run `mise run ums-direct-boot`, identify the disk again with `diskutil list`, and unmount it with `diskutil unmountDisk /dev/diskN`. Then run `mise run prepare-usb-boot-test`, `mise run write-usb-boot-test -- --check`, and `mise run write-usb-boot-test -- diskN`. The last command **writes** a persistent environment. After a successful read-back, power off, remove the PROG1 connection, power on, and use `diskutil list` to confirm the MIRROR appears as a USB disk without the RAM boot task. Recheck its disk number and unmount it before continuing. See [installation notes](docs/boot-environment.md) for prerequisites and limitations.
- **Flash:** Run `mise run flash-lemonade -- --check`, then `mise run flash-lemonade -- diskN` and follow the installer prompts. This **erases Android's `boot_b` and `userdata`**. Confirm the installer reports successful writes and read-back verification.
- **Boot Linux:** Run `mise run set-lemonade-boot -- --check`, then `mise run set-lemonade-boot -- diskN`. After successful read-back, power-cycle and connect via SSH using the settings supplied to the installer. **Stop and investigate before rebooting if any write or read-back fails.**
- **Optional camera setup:** Our OV5645 required additional configuration; see the [camera investigation](docs/camera-investigation.md) before applying it.

## Documentation

- [Downloads and fresh-checkout preparation](docs/downloads.md): where to get reference images and source, destination paths, hashes and known reproducibility blockers.
- [Hardware and boot-chain research](docs/boot-research.md): board identification, PROG1, reference images, U-Boot and shim experiments.
- [USB access and backup research](docs/usb-backup.md): development setup, RAM boot tasks, storage identification and backup experiments.
- [Boot environment and installation](docs/boot-environment.md): environment investigation, persistent USB boot test and LemonadeMirror installation.
- [Camera investigation](docs/camera-investigation.md): sensor diagnosis, OV5645 experiments and configuration.
- [Optional GUI and kiosk setup](docs/gui.md): I run Chromium in kiosk mode under Cage, with a systemd service to start it, rotate the display, and open a website. The notes also cover camera preview and experimental presence detection. The test configuration automatically grants camera and microphone requests; review its permissions before normal browsing.
- [Optional microphone setup](docs/mic.md): expose the mirror's microphone to Chromium through PipeWire, plus notes on the experimental browser sound meter.

## Repository layout

- `scripts/` — local extraction and experimental build scripts.
- `shim/` — shim source reproduced from the original guide, with local provenance comments. The fetch script verifies the original blocks before adding those comments.
- `reference-images/` — local, Git-ignored reference images manually downloaded from the material accompanying Gouda-percha's [MIRROR research and RAM-only boot guide](https://failedattempts.neocities.org/part3a), including `mmcblk2boot0.img` and `spl_0-60k.img`. Our extraction and boot scripts read these files; they are not provided by this repository or automatically downloaded by the setup task. They are reference files from another device, **not a backup of your own MIRROR**, and their compatibility with another unit is not guaranteed.
- `build/` — local, Git-ignored working files written by this project's scripts and `mise` tasks. These include downloaded LemonadeMirror release files and Linux sources, extracted boot components, compiled U-Boot and shim images, camera experiments, and generated configuration files. Some later tasks require specific paths and hashes here; do not assume the directory can be deleted without affecting those tasks.
- `vendor/` — local, Git-ignored checkouts of third-party source, including LemonadeMirror, NXP U-Boot, and NXP imx-mkimage. These are inputs to the project's build and preparation scripts, not code maintained in this repository. The U-Boot build script clones its checkout if missing; other checkouts must be supplied separately. Scripts check or read these sources and generally write generated outputs to `build/`.
- `pixi.toml` and `pixi.lock` — project-local UUU runtime libraries, installed into Git-ignored `.pixi/`.

## Credits and resources

This project builds on the work of the MIRROR hacking community and the maintainers of the tools and software used here. Thank you to:

- **Gouda-percha**, for documenting the MIRROR hardware, the `PROG1` boot-mode discovery, and the USB boot research in [Failed Attempts](https://failedattempts.neocities.org/), the [RAM-only boot guide](https://failedattempts.neocities.org/part3a) and the [XDA discussion](https://xdaforums.com/t/lululemon-mirror.4752046/post-90213865).
- **ikiiftekhar2 and the LemonadeMirror contributors**, for [LemonadeMirror](https://github.com/ikiiftekhar2/lemonademirror), its Debian image, [installation guide](https://github.com/ikiiftekhar2/lemonademirror/blob/main/docs/06-flash-image.md), and [boot-chain documentation](https://github.com/ikiiftekhar2/lemonademirror/blob/main/docs/boot-chain-anatomy.md).
- **git-nimrod and the Glass Panes Discord community**, for [Glass Panes](https://github.com/git-nimrod/glass-panes) and sharing their MIRROR knowledge and support.
- **NXP and contributors**, for the [Universal Update Utility (UUU)](https://github.com/nxp-imx/mfgtools), [i.MX U-Boot sources](https://github.com/nxp-imx/uboot-imx), and [imx-mkimage](https://github.com/nxp-imx/imx-mkimage), used for USB access and boot-image research.
