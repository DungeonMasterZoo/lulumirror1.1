# Hardware and boot-chain research

> This is a chronological research record. Statements about status and untested steps describe the time they were written, not necessarily the current state. Read the later entries and the [project overview](../README.md) before acting.

## Hardware and safety

The board is marked `Mirror V1.1 EVT rev A08`. In normal Android mode it appeared as `freescale mirror_v1_1`, with ADB unauthorized. In program mode, UUU detected `MX8MM SDP`, USB ID `1fc9:0134`.

The [original guide](https://failedattempts.neocities.org/) says its approach applies only to the i.MX8MM board. Check your own board before proceeding. The MIRROR is heavy and contains powered electronics; disconnect mains power before working on the exposed board. Flashing or modifying boot settings can destroy data or leave the device unbootable. Keep a verified backup of **your own** device before writing anything; the reference dumps here are not that backup.

## What we did

### 1. Entered program mode

Gouda-percha reports that connecting the two `PROG1` pads before powering on selects USB serial download mode. Their [earlier forum test](https://xdaforums.com/t/lululemon-mirror.4752046/post-90213865) used a 10 kΩ resistor; they later told us a direct wire connection also works. Our unit was detected after connecting the pads and powering on. Make the connection with power disconnected; do not adjust an exposed, powered board or let a jumper touch nearby components.

We installed NXP's [Universal Update Utility (UUU)](https://github.com/nxp-imx/mfgtools) and checked detection:

```sh
mise run usb
```

The expected result for our unit was `MX8MM`, `SDP`, `0x1FC9`, `0x0134`. Gouda-percha says the PROG connection is only needed at startup. This detection check does not send a boot image.

### 2. Prepared reference boot components

The original guide's [RAM-only boot procedure](https://failedattempts.neocities.org/part3a) describes loading a signed SPL followed by ATF, TEE, a device tree, custom U-Boot, and a shim. The files downloaded into `reference-images/` include the author's reference `mmcblk2boot0.img` and `spl_0-60k.img`. The SPL file is **384 KiB (0x60000 bytes)**; the name should not be interpreted as 60 KiB. Its compatibility with another unit has not been established.

We inspected the boot0 image's FIT component table, then extracted stock U-Boot, ATF, TEE and the bootloader device tree using the recorded positions and sizes. The script includes source links, explains the offsets, reports SHA-256 hashes, and refuses to overwrite different output files:

```sh
python3 scripts/extract-boot-components.py
```

Outputs are in `build/extracted-boot-components/`. These are extracted from a **reference image**, not verified against our MIRROR. The downloaded `mmcblk2rpmb.img` is a 40-byte permission-denied message, not an RPMB dump. See [LemonadeMirror's boot-chain notes](https://github.com/ikiiftekhar2/lemonademirror/blob/main/docs/boot-chain-anatomy.md) for why boot0 and its FIT matter and why offsets can differ by build.

The FIT identifies stock U-Boot's load address as `0x40200000`, and its device tree identifies an i.MX8MM EVK. The extracted stock U-Boot reports `2020.04-00002-g9d472cf` and contains fastboot-related strings. This does not establish that it can replace the guide's custom build or provide a USB command prompt. NXP's [Android 10.0.0_2.5.0 EVK configuration](https://github.com/nxp-imx/uboot-imx/blob/d26632454196662187c2562e404655fa88eea4cb/configs/imx8mm_evk_defconfig) is a possible research baseline: it uses the same load address and enables fastboot, but its exact relationship to the reference build and required custom changes are unknown.

That NXP baseline enables `CONFIG_FASTBOOT_UUU_SUPPORT` and `CONFIG_FSL_FASTBOOT`; the [corresponding implementation](https://github.com/nxp-imx/uboot-imx/blob/d26632454196662187c2562e404655fa88eea4cb/drivers/fastboot/fb_fsl/fb_fsl_command.c) accepts `UCmd`/`ACmd` to run U-Boot commands. This is a research lead, not confirmation of working USB command output or board support. The baseline also enables fastboot flashing and MMC environment storage, so it is **not a safe read-only build** and must not be sent to the MIRROR.

`mise run uboot-baseline` attempts a local experimental build. After `mise run setup`, it fetches the pinned NXP source if absent, checks the revision and checkout for unexpected changes, and applies `patches/uboot-macos-image-tool-data-section.patch` to the host image tools before compiling with project-local GNU Make and sed. Each run uses a new `build/uboot-nxp-task.*` directory. The patch is a local Apple Silicon host-linker workaround, not a proven fix for the target. A successful build would still be an unverified EVK baseline, not the author's custom U-Boot.

An earlier local build emitted repeated shell `[: too many arguments` diagnostics from the Makefile's macOS version checks. The build script now supplies the detected version components explicitly; a fresh build completed without those diagnostics and produced the same binary hash as the earlier build. Other compiler and linker warnings remain and have not been fully assessed. Neither a successful build nor matching hashes establish device compatibility.

`mise run uboot-research` builds a separate experimental variant intended to start `fastboot 0`, use an in-memory environment rather than an MMC-backed one, and omit `saveenv`; its script checks that Kconfig retains these settings and checks the compiled default boot command. The EVK board header unconditionally overrides `CONFIG_BOOTCOMMAND` in the original source, so the build applies `patches/uboot-evk-bootcommand-guard.patch` to respect the configured value. This is **not a read-only or device-safe bootloader**: NXP's UUU support selects the FSL fastboot implementation, which depends on fastboot flashing, and UUU commands can run arbitrary U-Boot commands. Nor does changing the environment prevent other code from writing storage or hardware registers.

One research build succeeded with `bootcmd=fastboot 0` confirmed in its binary; the earlier `CONFIG_BOOTCOMMAND` redefinition warning and macOS version-test errors were absent. Other compiler and linker warnings remain. The extracted reference device tree describes NXP PTN5110 USB-C controllers at I2C addresses `0x50` and `0x52`, matching the EVK source's controller addresses, but a reference description is not proof that either controller exists on this MIRROR or that `fastboot 0` reaches its micro-USB port.

Further differences need resolution before any device test: the baseline uses `CONFIG_OF_SEPARATE`, selecting its appended EVK control device tree, not automatically the reference tree loaded at `0x43000000`; the shim passes that reference address to ATF/TEE, not explicitly as U-Boot's BL33 FDT argument. Decompiling the reference tree and one built tree with the same `dtc` yielded identical DTS text, although their binary files differ and the reference has two extra trailing bytes. This does not establish compatibility with the physical MIRROR. EVK board initialization probes USB-C controllers over I2C, although the MIRROR's connector and wiring are not confirmed to match.

The original fastboot buffer begins at `0x42800000` and spans 1 GiB, including the guide's separate FDT address. The research configuration reduces it to 8 MiB, ending at `0x43000000`, and verifies those Kconfig values. This prevents that particular declared overlap but does not prove the buffer is free from relocated U-Boot, runtime allocations, other firmware, or environment overrides. NXP source registers a fastboot output device that sends `INFO` responses, and its UUU `UCmd` handler executes commands, but initialization, console routing, host behavior and actual board communication are still untested.

Build-warning review: the log includes Apple host-tool deprecation and format warnings, misspelled header guards in the NXP source, target array-bounds warnings around low-level hardware pointers, GNU Make peer-target warnings, and an RWX ELF segment warning. None alone establishes runtime failure, and none has been fully cleared or validated for the target. They should not be dismissed as harmless without further analysis.

### 3. Prepared an experimental shim build

The [guide](https://failedattempts.neocities.org/part3a) includes shim source and build commands. We saved a reproducible source-fetch script and compiled a raw shim locally:

```sh
python3 scripts/get-shim-source.py
sh scripts/build-shim-experimental.sh
```

The source-fetch script checks pinned hashes. The initial build used `aarch64-elf-gcc` 16.2.0 and binutils 2.47; the current build uses mise's xPack toolchain and reports its versions and output hashes. It produces `build/shim-xpack/shim.bin`, **not** a finished `shim.imx`. The output has not been validated on the MIRROR. The build script refuses to overwrite existing outputs.

The xPack GCC 15.2.1 / binutils 2.45.1 rebuild produced a raw binary byte-for-byte identical to the earlier GCC 16.2.0 build (SHA-256 `33b583d78c8b0b008d3645e9b65feb511253c6dff81b401d62d28bb6e57dd1e2`). Its ELF header identifies AArch64 and entry point `0x40000040`, matching the guide. These checks do not verify execution, memory initialization, the required image header, or device compatibility.

We also checked out [NXP's imx-mkimage](https://github.com/nxp-imx/imx-mkimage) at commit `1b577853ae1afe1f26cdef27548da52fb424af48`. With that checkout at `vendor/nxp-imx-mkimage`, `mise run shim-package` builds its i.MX8M packer, packages the raw shim, and checks the resulting header and payload. Each run creates a fresh `build/shim-package.*` directory. The packer uses the macOS host compiler and system zlib, and currently emits two host format warnings. The task checks the source revision and refuses a locally modified packer.

Static verification found IVT bytes `d1 00 20 41` at offset 0, self address `0x40000000`, entry `0x40000040`, and the exact raw shim at offset `0x40`. The unsigned output is 9,728 bytes with SHA-256 `4e29cfa5230758619fbc82a730e940dc11d85d21ebc0dcdd0f4249a1d29e2281`; its CSF pointer points into zero padding, not a signature. NXP's packer also reports boot-data start `0x3ffffc00`, below the guide's DDR base. The matching-era NXP `f_sdp.c` jump handler checks the IVT tag and jumps to the entry, rather than using boot-data fields, but the actual reference SPL's exact source and behavior have not been established. These static checks do not prove the image will run or be accepted. **Do not send it to a device.**

## What's left

1. Validate or reconstruct the required custom U-Boot behavior and independently resolve the shim image's boot-data/CSF assumptions for the actual SPL. The guide's custom U-Boot build link is marked TODO.
2. Verify the SPL and extracted components are appropriate for the target unit; hashes identify files but do not prove compatibility or authenticity.
3. Determine whether the resulting USB fastboot interface supports the U-Boot commands needed without UART. The published [LemonadeMirror installer](https://github.com/ikiiftekhar2/lemonademirror/blob/main/docs/06-flash-image.md) uses a UART U-Boot prompt and assumes access has already been obtained.
4. Before installation, resolve how temporary RAM-loaded U-Boot relates to LemonadeMirror's documented persistent boot using stock U-Boot and `saveenv`. Back up the actual device and verify the target disk before any writes. The installer guide notes that restoring its backup has not yet been tested end to end.

The ready-made LemonadeMirror installer avoids building the Linux system from scratch, but it overwrites Android's `boot_b` and `userdata` partitions. Do not run it until the access and backup steps are understood and verified.
