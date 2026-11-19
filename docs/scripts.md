TODO: Replace instances of Mise run with raw command
[tasks.usb]
description = "List devices recognized by UUU and ADB (read-only)"
depends = [{ task = "uuu", args = ["-lsusb"] }]
run = "adb devices -l"

[tasks.uuu]
description = "Run UUU using project-local libraries; arguments may write to hardware"
run = "sh scripts/uuu-runner.sh"

[tasks.setup]
description = "Install project-local UUU runtime libraries"
run = "pixi install --locked"

[tasks.spl-test]
description = "Execute reference SPL in device RAM using sudo; no flash command"
run = "sh scripts/test-reference-spl.sh"

[tasks.atf-test]
description = "Write reference ATF to RAM using SDPV and sudo; no flash or jump"
run = "sh scripts/test-reference-atf.sh"

[tasks.tee-test]
description = "Write reference TEE to RAM using SDPV and sudo; no flash or jump"
run = "sh scripts/test-reference-tee.sh"

[tasks.uboot-test]
description = "Write experimental U-Boot to RAM using SDPV and sudo; no flash or jump"
run = "sh scripts/test-research-uboot.sh"

[tasks.uboot-ums-test]
description = "Write UMS-handoff U-Boot to RAM using SDPV; no flash or jump"
run = "sh scripts/test-ums-uboot.sh"

[tasks.ums-boot]
description = "Execute experimental RAM-only boot sequence for later writable UMS"
run = "sh scripts/boot-ums-research.sh"

[tasks.ums-direct-boot]
description = "Execute experimental RAM-only boot that immediately starts writable UMS"
run = "MIRROR_UMS_VARIANT=direct sh scripts/boot-ums-research.sh"

[tasks.fdt-test]
description = "Write reference device tree to RAM using SDPV and sudo; no flash or jump"
run = "sh scripts/test-reference-fdt.sh"

[tasks.shim-test]
description = "Write experimental shim to RAM using SDPV and sudo; no flash or jump"
run = "sh scripts/test-research-shim.sh"

[tasks.shim-jump]
description = "Execute loaded experimental shim via SDPV; no flash command"
run = "sh scripts/jump-research-shim.sh"

[tasks.uboot-version]
description = "Ask temporary U-Boot to print its version over USB"
run = "sh scripts/test-uboot-version.sh"

[tasks.uboot-output]
description = "Temporarily route U-Boot stdout to fastboot; no saveenv"
run = "sh scripts/route-uboot-output.sh"

[tasks.mmc-list]
description = "List MMC devices via temporary U-Boot; no storage write"
run = "sh scripts/list-uboot-mmc.sh"

[tasks.mmc-inspect]
description = "Select MMC 2 user area and inspect its capacity and partitions"
run = "sh scripts/inspect-uboot-mmc2.sh"

[tasks.backup-expose]
description = "Attempt to expose MMC 2 as a writable USB disk; no flash command"
run = "sh scripts/expose-backup-disk.sh"

[tasks.backup-copy]
description = "Verify and copy a selected MIRROR user-area disk to Downloads"
run = "python scripts/backup-mirror-user.py"

[tasks.inspect-backup-env]
description = "Scan user-area backup for possible U-Boot environment, read-only"
run = "python scripts/inspect-backup-env.py"

[tasks.test-env-format]
description = "Test U-Boot environment encoding locally without device access"
run = "python scripts/test-env-format.py"

[tasks.probe-reference-boot0]
description = "Compare boot0 to reference in RAM over USB; no block writes"
run = "sh scripts/probe-reference-boot0.sh"

[tasks.prepare-usb-boot-test]
description = "Prepare an offline candidate stock U-Boot USB boot environment"
run = "python scripts/prepare-usb-boot-test.py"

[tasks.write-usb-boot-test]
description = "Write and verify approved 4 KiB persistent USB boot test"
run = "python scripts/write-usb-boot-test.py"

[tasks.set-lemonade-boot]
description = "Replace USB test boot command with LemonadeMirror's persistent boot command"
run = "python scripts/set-lemonade-boot.py"

[tasks.prepare-camera-clock-test]
description = "Build offline camera CLKO1 device-tree candidate; no device access"
run = "python scripts/prepare-camera-clock-test.py"

[tasks.test-camera-clock]
description = "Install experimental camera-clock DTB over SSH with backup; no reboot"
run = "sh scripts/test-camera-clock.sh"

[tasks.restore-camera-dtb]
description = "Restore original Linux device tree over SSH; no reboot"
run = "sh scripts/restore-camera-dtb.sh"

[tasks.sample-camera-probe]
description = "Sample camera GPIO and clock during one driver reprobe over SSH"
run = "sh scripts/sample-camera-probe.sh"

[tasks.build-camera-timing]
description = "Build experimental OV5640 timing module locally in Linux Docker"
run = "sh scripts/build-camera-timing.sh"

[tasks.build-camera-polarity]
description = "Build experimental OV5640 powerdown-polarity module locally"
run = "CAMERA_BUILD_VARIANT=polarity sh scripts/build-camera-timing.sh"

[tasks.build-camera-ov5645]
description = "Build temporary OV5645 driver adapted to existing Mirror DT"
run = "CAMERA_BUILD_VARIANT=ov5645 sh scripts/build-camera-timing.sh"

[tasks.test-camera-timing]
description = "Temporarily test OV5640 timing module over SSH and restore original"
run = "sh scripts/test-camera-timing.sh"

[tasks.test-camera-polarity]
description = "Temporarily test OV5640 powerdown polarity and restore original"
run = "CAMERA_TEST_VARIANT=polarity sh scripts/test-camera-timing.sh"

[tasks.test-camera-ov5645]
description = "Temporarily test OV5645 sensor binding and restore camera service"
run = "sh scripts/test-camera-ov5645.sh"

[tasks.test-camera-ov5645-capture]
description = "Temporarily test OV5645 capture to /dev/null and restore camera service"
run = "CAMERA_OV5645_MODE=capture sh scripts/test-camera-ov5645.sh"

[tasks.extract-android-kernel]
description = "Extract stock Android kernel from backup, read-only and offline"
run = "python scripts/extract-android-kernel.py"

[tasks.prepare-ov5645-dtb]
description = "Prepare stock-driver OV5645 device tree locally"
run = "python scripts/prepare-ov5645-dtb.py"

[tasks.prepare-ov5645-camhub]
description = "Prepare OV5640/OV5645-compatible camera hub scripts locally"
run = "python scripts/prepare-ov5645-camhub.py"

[tasks.install-ov5645]
description = "Install OV5645 DT and camera scripts with verified recovery copies"
run = "OV5645_ACTION=install sh scripts/ov5645-persistent.sh"

[tasks.restore-ov5645]
description = "Restore original camera DT and scripts from recovery copies"
run = "OV5645_ACTION=restore sh scripts/ov5645-persistent.sh"

[tasks.lemonade-download]
description = "Download and hash-check pinned LemonadeMirror release files"
run = "sh scripts/download-lemonade-release.sh"

[tasks.flash-lemonade]
description = "Verify MIRROR and run upstream installer; erases boot_b and userdata"
run = "python scripts/flash-lemonade.py"

[tasks.extract]
description = "Extract or verify reference boot components locally"
run = "python scripts/extract-boot-components.py"

[tasks.shim-source]
description = "Fetch and verify the shim source from the original guide"
run = "python scripts/get-shim-source.py"

[tasks.shim-build]
description = "Build the experimental raw shim locally; does not contact the device"
run = "sh scripts/build-shim-experimental.sh"

[tasks.shim-package]
description = "Package and statically check the experimental shim; do not deploy"
run = "sh scripts/package-shim-experimental.sh"

[tasks.uboot-baseline]
description = "Build unverified NXP EVK baseline locally; never send to a device"
run = "sh scripts/build-uboot-baseline.sh"

[tasks.uboot-research]
description = "Build experimental fastboot research configuration locally; not device-safe"
run = "sh scripts/build-uboot-baseline.sh research"

[tasks.uboot-ums-build]
description = "Build untested fastboot-then-writable-UMS U-Boot locally"
run = "sh scripts/build-uboot-baseline.sh backup-ums"

[tasks.uboot-direct-ums-build]
description = "Build untested direct-writable-UMS U-Boot locally"
run = "sh /code/scripts/build-uboot-baseline.sh backup-ums-direct"
