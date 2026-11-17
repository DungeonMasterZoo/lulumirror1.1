# Local patches

These six patches support camera investigations and experimental U-Boot builds.
Keeping a patch here does not mean it is installed on the MIRROR. The status
below reflects recorded tests and cleanup, not a fresh inspection of the device.

## Camera patches

The camera build scripts select **one of these patches per variant**. They are
not applied together. Building a module locally does not install it.

### `ov5640-invert-powerdown.patch`

- **Changes:** Reverses the OV5640 driver's powerdown GPIO values during power
  transitions and changes its initial GPIO request from high to low.
- **Purpose:** Test whether powerdown polarity prevented the sensor from
  responding.
- **Observed result:** The sensor responded over I2C with chip ID `0x5645`.
  The OV5640 driver expected `0x5640` and rejected it. This identified the need
  to investigate the dedicated OV5645 driver, not simply bypass the ID check.
- **Cleanup:** The test module was removed, the original module was reloaded
  and its on-disk hash checked, and `camhub` was restarted.
- **Build task:** `mise run build-camera-polarity`.

### `ov5640-vendor-reset-delay.patch`

- **Changes:** Increases the delay between enabling the sensor and releasing
  reset from 1–2 ms to 5–6 ms, matching the vendor driver's 5 ms delay.
  It does not change polarity, regulator voltages, or the post-reset delay.
- **Purpose:** Test whether the original probe failure was a timing issue.
- **Observed result:** The experimental module loaded, but the sensor still
  failed to bind with the same register errors.
- **Cleanup:** The test module was unloaded, the original module was reloaded
  and its on-disk hash checked, and `camhub` was restarted.
- **Build task:** `mise run build-camera-timing`.

### `ov5645-mirror-probe.patch`

- **Changes:** Adapts the dedicated OV5645 driver to the existing Mirror device
  tree without replacing that tree:
  - Uses supply names `DOVDD`, `AVDD`, and `DVDD` instead of
    `vdddo`, `vdda`, and `vddd`, retaining the existing supply mappings.
  - Requests the GPIO named `powerdown` as an active-high enable, initially low.
  - Temporarily accepts the `ovti,ov5640` compatible string.
- **Purpose:** Test the OV5645 driver after the polarity experiment revealed
  chip ID `0x5645`. The patch does not change regulator voltage settings.
- **Observed result:** The driver bound and logged `OV5645 detected`. A later
  capture test returned 15 frame markers, but frame contents were not inspected
  and CSI frame-start and CRC errors occurred. This did not establish reliable
  image capture.
- **Cleanup:** The first probe test required manual unbinding before module
  removal. The later capture test successfully unbound the sensor, removed the
  test module, verified the original module state and file hash, and restarted
  `camhub`.
- **Build task:** `mise run build-camera-ov5645`.

### Were the camera changes reversed?

**The temporary patched modules were removed after testing. The later
persistent camera configuration changes were not restored to baseline.**

The later setup uses the stock OV5645 driver with a modified device tree and
camera scripts, rather than keeping the patched probe module installed. During
kiosk cleanup, the camera changes were deliberately retained:

| Device path | Last recorded state |
| --- | --- |
| `imx8mm-mirror.dtb` on `/dev/mmcblk2p4` | OV5645 boot configuration retained. |
| `/usr/local/sbin/camhub.sh` | OV5645 handling and experimental byte-swap pipeline retained. |
| `/usr/local/sbin/camset.sh` | Sensor-aware OV5645 setup retained. |
| `/home/mirror/uyvy-swap-stream` | Executable retained for the active `camhub.sh`. |
| `/home/mirror/mirror-ov5645-recovery.bak/` | Original `original.dtb`, `camhub.sh`, and `camset.sh` backups retained. |

No live restore was recorded. `mise run restore-ov5645` coordinates restoration
of the three original files, but the cleanup notes record that the active
byte-swap version of `camhub.sh` is not in its hash allowlist. The restore
therefore rejects that version; the live restore has not been validated.
Do not treat the existence of the restore task as proof that rollback is ready.

Sources: [camera investigation](../docs/camera-investigation.md) and
[cleanup state and restore limitation](../docs/kiosk/DELETED.md#what-is-left).

## U-Boot patches

### `uboot-macos-image-tool-data-section.patch`

- **Changes:** Moves macOS host image-tool registration sections from Mach-O
  `__TEXT` to `__DATA`, updating both section declarations and lookup code.
- **Purpose:** Local Apple Silicon host-linker workaround.
- **Scope:** Host build tools, not the device's boot-command behavior.

### `uboot-evk-bootcommand-guard.patch`

- **Changes:** Wraps the EVK board header's default `CONFIG_BOOTCOMMAND` in
  `#ifndef CONFIG_BOOTCOMMAND`.
- **Purpose:** Preserve an explicitly configured command, such as `fastboot 0`
  or `ums 0 mmc 2`, instead of letting the board header overwrite it.

### `uboot-direct-ums-usb-boot.patch`

- **Changes:** Disables two NXP USB-boot overrides in `common/autoboot.c`:
  the USB manufacturing-mode branch and the later substitution of
  `bootcmd_mfg` for the selected command.
- **Purpose:** Let the experimental direct-UMS image retain its explicit
  `ums 0 mmc 2` command when booted over USB.
- **Observed result:** The first direct-UMS image, before this patch, appeared
  as fastboot and exposed no disk. The revised image containing this patch
  was built and checked locally; its hardware behavior is recorded as untested.
- **Warning:** This is ordinary **writable** USB mass storage, not a read-only
  backup interface or write blocker.

### Build application and rollback status

[`scripts/build-uboot-baseline.sh`](../scripts/build-uboot-baseline.sh) applies
the host-tool and EVK boot-command patches to the shared pinned vendor checkout.
For the `backup-ums-direct` variant, it creates an isolated source copy and
applies all three patches there. The USB override patch does not affect the
other build modes.

**No persistent experimental U-Boot installation is recorded.** The documented
hardware experiments transferred images into RAM and, in separate execution
steps, ran temporary firmware. They issued no intentional flash, erase, or
`saveenv` command. A power cycle discards the temporary RAM-loaded firmware,
so there is no recorded installed U-Boot replacement to roll back.

This is not proof that arbitrary experimental firmware cannot write storage.
The images contain storage-writing capabilities, and UMS exposes a writable
disk. The recorded command sequence is not a fresh verification that device
storage is unchanged.

Patch files and local build artifacts remain for reproducibility; they were
not removed or reversed as part of device cleanup.

Sources: [boot research](../docs/boot-research.md) and
[USB experiments and RAM-only procedures](../docs/usb-backup.md).
