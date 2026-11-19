# Downloads and fresh-checkout preparation

This is a checklist of the external files and source checkouts used in this journal. Run commands from the repository root. The paths below are local and Git-ignored; they are not included in a fresh clone. Do not overwrite existing files or checkouts without inspecting them first.

**This is not yet a reproducible one-command installer.** Some tasks expect hashes and paths from builds on my Mac, and disk-writing scripts check my unit's partition GUIDs and layout. A hash match identifies a file, not its authenticity or compatibility with another MIRROR. Do not bypass checks to flash a different device.

For the camera preparation and build scripts, provide a clean [LemonadeMirror source checkout](https://github.com/ikiiftekhar2/lemonademirror) at the revision used for my camera work. If the destination does not already exist:

```sh
git clone https://github.com/ikiiftekhar2/lemonademirror.git vendor/lemonademirror
git -C vendor/lemonademirror checkout --detach 900b4ca4c0f7152be96108bb7f4a2d15bd10c1bb
```

The camera module build requires Docker and downloads the pinned Linux 6.18.60 source archive into `build/` if absent. Camera changes are optional and device-specific; see [camera investigation](camera-investigation.md).

## 4. Local build outputs and limitations

The shim source is already in `shim/`; `sh /code/scripts/build-shim-experimental.sh` builds the raw shim, and `sh /code/scripts/package-shim-experimental.sh` packages it using the checkout above. `sh /code/scripts/build-uboot-baseline.sh research` and `sh /code/scripts/build-uboot-baseline.sh backup-ums-direct` create experimental U-Boot builds. These commands create new directories in `build/` and do not send firmware to a device.

**Fresh-build blocker:** The scripts for `ums-direct-boot`, the boot0 comparison, and some camera tasks refer to exact directories from my machine, such as `build/uboot-nxp-task.LHWaKn/` and `build/shim-package.dvxmz4/`, and may also require exact binary hashes. New builds use different directory names; they are not automatically selected, and matching source versions do not guarantee identical binaries. The environment and backup scripts additionally enforce my disk's identity. Review and adapt the scripts for your hardware rather than treating the TL;DR as a tested fresh-install recipe. `--check` modes are useful for locating missing inputs, but passing them does not establish hardware safety or compatibility.

### Using this on another MIRROR

- **Find your own build outputs:** The build commands print their output directories. To list possible U-Boot, shim, and camera artifacts afterward, run `find build -type f \( -name u-boot.bin -o -name shim.imx -o -name ov5645.ko -o -name ov5640.ko \) -print`. Identify the correct build variant from its build output; do not assume the newest file is the right one.
- **Inspect the hash:** Run `sha256sum path/to/your/file` and compare it with the relevant script's expected hash. A match identifies the same bytes as my file; it does not prove compatibility with your hardware. A different hash needs investigation, not automatic acceptance.
- **Find the hard-coded inputs:** Review `scripts/test-ums-uboot.sh`, `scripts/test-research-uboot.sh`, and `scripts/test-research-shim.sh` for the RAM-boot paths and hashes. `scripts/prepare-usb-boot-test.py`, `scripts/test-env-format.py`, and the camera preparation and test scripts also refer to specific build paths. The composite tasks call these scripts, so an individual missing input can stop the whole sequence.
- **Treat disk checks separately:** `scripts/backup-mirror-user.py` checks partition GUIDs from my MIRROR; `scripts/write-usb-boot-test.py` and the flash and boot-setting scripts build on those checks and make additional assumptions about disk size, environment location, and original bytes. Your unit can differ even if the model matches.
- **Do not blindly change or bypass checks:** Independently verify the board, boot chain, disk identity and layout, environment location, and original bytes against your own verified backup before considering changes. The write path and restoration process have not been validated for other units. Use the scripts' `--check` modes where available to inspect local prerequisites; they do not authorize a device write or prove the firmware is safe.
