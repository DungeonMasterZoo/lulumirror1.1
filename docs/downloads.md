# Downloads and fresh-checkout preparation

This is a checklist of the external files and source checkouts used in this journal. Run commands from the repository root. The paths below are local and Git-ignored; they are not included in a fresh clone. Do not overwrite existing files or checkouts without inspecting them first.

**This is not yet a reproducible one-command installer.** Some tasks expect hashes and paths from builds on my Mac, and disk-writing scripts check my unit's partition GUIDs and layout. A hash match identifies a file, not its authenticity or compatibility with another MIRROR. Do not bypass checks to flash a different device.

## 1. Tools and LemonadeMirror release

On Apple Silicon macOS, install [mise](https://mise.jdx.dev/getting-started.html) and Apple's command-line developer tools. Review `mise.toml`, then run:

```sh
mise install
pixi install --locked
sh scripts/download-lemonade-release.sh
```

The last command downloads and verifies the pinned `v1.0-kernel-6.18.60` installer, boot image, and compressed root filesystem from [LemonadeMirror releases](https://github.com/ikiiftekhar2/lemonademirror/releases/tag/v1.0-kernel-6.18.60) into `build/lemonademirror-v1.0-kernel-6.18.60/`. It does not contact the MIRROR. Other operating systems need equivalent tools; the bundled UUU setup targets Apple Silicon macOS.

## 2. Reference boot images

Create the destination with `mkdir -p reference-images`. Download these files manually:

| Destination | Source | Purpose |
| --- | --- | --- |
| `reference-images/mmcblk2boot0.img` | [Gouda-percha's MEGA image folder](https://mega.nz/folder/QdsizKTQ#IPVMSXyopW1ozWQLTOQRSQ), linked from [Part 2b](https://failedattempts.neocities.org/part2b.html) | Reference boot0 image used to extract ATF, TEE and the device tree, and for the boot0 comparison. |
| `reference-images/spl_0-60k.img` | SPL download linked in [Part 3a](https://failedattempts.neocities.org/part3a) | Reference SPL for the experimental USB RAM boot. Despite the name, the file is 384 KiB. |

The MEGA folder also provides `mmcblk2boot1.img` and `mmcblk2.img` (the compressed user-area image), but those are not needed by the RAM-boot tasks above.

Check the two boot inputs against the hashes used in this project:

```sh
shasum -a 256 -c scripts/reference-checksum
```

Extract the reference boot components locally with `mise run extract`. `mise run spl-test -- --check` checks the SPL and local dependencies without contacting the device. The boot0 comparison expects this exact reference file, including its original length.

## 3. Third-party source checkouts

`mise run uboot-direct-ums-build` automatically clones [NXP U-Boot](https://github.com/nxp-imx/uboot-imx) into `vendor/uboot-imx-android-10/` if it is absent, verifies revision `d26632454196662187c2562e404655fa88eea4cb`, and applies the project's patches. It builds experimental code locally; it does not contact the MIRROR.

For shim packaging, the script expects [NXP imx-mkimage](https://github.com/nxp-imx/imx-mkimage) at a pinned revision. If the destination does not already exist:

```sh
mkdir -p vendor
git clone https://github.com/nxp-imx/imx-mkimage.git vendor/nxp-imx-mkimage
git -C vendor/nxp-imx-mkimage checkout --detach 1b577853ae1afe1f26cdef27548da52fb424af48
```

For the camera preparation and build scripts, provide a clean [LemonadeMirror source checkout](https://github.com/ikiiftekhar2/lemonademirror) at the revision used for my camera work. If the destination does not already exist:

```sh
mkdir -p vendor
git clone https://github.com/ikiiftekhar2/lemonademirror.git vendor/lemonademirror
git -C vendor/lemonademirror checkout --detach 900b4ca4c0f7152be96108bb7f4a2d15bd10c1bb
```

The camera module build requires Docker and downloads the pinned Linux 6.18.60 source archive into `build/` if absent. Camera changes are optional and device-specific; see [camera investigation](camera-investigation.md).

## 4. Local build outputs and limitations

The shim source is already in `shim/`; `mise run shim-build` builds the raw shim, and `mise run shim-package` packages it using the checkout above. `mise run uboot-research` and `mise run uboot-direct-ums-build` create experimental U-Boot builds. These commands create new directories in `build/` and do not send firmware to a device.

**Fresh-build blocker:** The scripts for `ums-direct-boot`, the boot0 comparison, and some camera tasks refer to exact directories from my machine, such as `build/uboot-nxp-task.LHWaKn/` and `build/shim-package.dvxmz4/`, and may also require exact binary hashes. New builds use different directory names; they are not automatically selected, and matching source versions do not guarantee identical binaries. The environment and backup scripts additionally enforce my disk's identity. Review and adapt the scripts for your hardware rather than treating the TL;DR as a tested fresh-install recipe. `--check` modes are useful for locating missing inputs, but passing them does not establish hardware safety or compatibility.

### Using this on another MIRROR

- **Find your own build outputs:** The build commands print their output directories. To list possible U-Boot, shim, and camera artifacts afterward, run `find build -type f \( -name u-boot.bin -o -name shim.imx -o -name ov5645.ko -o -name ov5640.ko \) -print`. Identify the correct build variant from its build output; do not assume the newest file is the right one.
- **Inspect the hash:** Run `shasum -a 256 path/to/your/file` and compare it with the relevant script's expected hash. A match identifies the same bytes as my file; it does not prove compatibility with your hardware. A different hash needs investigation, not automatic acceptance.
- **Find the hard-coded inputs:** Review `scripts/test-ums-uboot.sh`, `scripts/test-research-uboot.sh`, and `scripts/test-research-shim.sh` for the RAM-boot paths and hashes. `scripts/prepare-usb-boot-test.py`, `scripts/test-env-format.py`, and the camera preparation and test scripts also refer to specific build paths. The composite tasks call these scripts, so an individual missing input can stop the whole sequence.
- **Treat disk checks separately:** `scripts/backup-mirror-user.py` checks partition GUIDs from my MIRROR; `scripts/write-usb-boot-test.py` and the flash and boot-setting scripts build on those checks and make additional assumptions about disk size, environment location, and original bytes. Your unit can differ even if the model matches.
- **Do not blindly change or bypass checks:** Independently verify the board, boot chain, disk identity and layout, environment location, and original bytes against your own verified backup before considering changes. The write path and restoration process have not been validated for other units. Use the scripts' `--check` modes where available to inspect local prerequisites; they do not authorize a device write or prove the firmware is safe.
