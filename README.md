# Repurposing a Lululemon MIRROR
> [!WARNING]
> This project is ongoing. Until this notice is modified, this project is not expected to function.

> [!WARNING]
> This is hardware hacking. if you don't feel comfortable manually bridging pins on a circuit board, this isn't the project for you. This is open-source stuff, no implied or express warranty.

This is a fork of Jmurzy's process of getting [LemonadeMirror](https://github.com/ikiiftekhar2/lemonademirror), a Debian-based system, running on a MIRROR with the original NXP i.MX8M Mini board. This version is stripped to bare essentials, and simplified where possible. The original project is run on an apple silicon mac, using Mise. For this version, I have foregone mise in favor of a more reproducable dockerfile. While  this aims to be system-agnostic, it was written from my Arch Linux PC.

The original repo suggests you point an llm agent at the repo in order to give it needed context to help you. If I've done my job well, no such agent should be needed. YMMV.

# Steps
## Prerequisites
Docker
## Setting up your environment
Clone this repository with
```sh
git clone https://github.com/DungeonMasterZoo/lulumirror1.1/
cd lulumirror1.1
```

Set up your docker environment with
```sh
docker build . -t lulumirror
```
### Acquiring reference images
Create a new folder called `reference-images`
Then, download
`reference-images/spl_0-60k.img` (Reference boot0 image used to extract ATF, TEE and the device tree, and for the boot0 comparison.) and
`reference-images/mmcblk2boot0.img` (Reference Secondary Program Loader (SPL) for the USB RAM boot.)
from [Gouda-percha's MEGA image folder](https://mega.nz/folder/QdsizKTQ#IPVMSXyopW1ozWQLTOQRSQ), linked from [Part 2b](https://failedattempts.neocities.org/part2b.html)

### Downloading tools and repos
Enter into the docker environment with
```sh
docker run -ti --rm -v $PWD:/code -v /dev:/dev lulumirror
```
Get the pinned version of lemonademirror with
```sh
sh /code/scripts/download-lemonade-release.sh
```
Check the two boot inputs against the hashes used in this project:

```sh
sha256sum -c /code/scripts/reference-checksum
```
Extract the reference boot components from the reference images with
```sh
python3 /code/scripts/extract-boot-components.py
```
Build a patched uboot image with
```sh
sh /code/scripts/build-uboot-baseline.sh backup-ums-direct
```

The script for packaging the shim expects[NXP imx-mkimage](https://github.com/nxp-imx/imx-mkimage) at a pinned revision, grab it with
```sh
git clone https://github.com/nxp-imx/imx-mkimage.git vendor/nxp-imx-mkimage
git -C vendor/nxp-imx-mkimage checkout --detach 1b577853ae1afe1f26cdef27548da52fb424af48
```
TODO: CAMERA SETUP

Build the shim with
```sh
sh /code/scripts/build-shim-experimental.sh
```
Package it with
```sh
sh /code/scripts/package-shim-experimental.sh
```
## License
Original code and documentation in this repository are available under the [MIT License](LICENSE). Third-party material, including the reproduced shim source and patches to upstream projects, is excluded from that grant. See
[license scope and third-party notices](THIRD_PARTY_NOTICES.md) for details.

## Credits and resources

This repository is built on the shoulders of those who've come prior. They laid the groundwork to make this possible. Thank you to:

- **Jmurzy**, for the original [Mirror1.1 repo](https://github.com/Jmurzy/Mirror1.1)
- **Gouda-percha**, for documenting the MIRROR hardware, the `PROG1` boot-mode discovery, and the USB boot research in [Failed Attempts](https://failedattempts.neocities.org/), the [RAM-only boot guide](https://failedattempts.neocities.org/part3a) and the [XDA discussion](https://xdaforums.com/t/lululemon-mirror.4752046/post-90213865).
- **ikiiftekhar2 and the LemonadeMirror contributors**, for [LemonadeMirror](https://github.com/ikiiftekhar2/lemonademirror), its Debian image, [installation guide](https://github.com/ikiiftekhar2/lemonademirror/blob/main/docs/06-flash-image.md), and [boot-chain documentation](https://github.com/ikiiftekhar2/lemonademirror/blob/main/docs/boot-chain-anatomy.md).
- **git-nimrod and the Glass Panes Discord community**, for [Glass Panes](https://github.com/git-nimrod/glass-panes) and sharing their MIRROR knowledge and support.
- **NXP and contributors**, for the [Universal Update Utility (UUU)](https://github.com/nxp-imx/mfgtools), [i.MX U-Boot sources](https://github.com/nxp-imx/uboot-imx), and [imx-mkimage](https://github.com/nxp-imx/imx-mkimage), used for USB access and boot-image research.
