# License scope and third-party notices

The [MIT license](LICENSE) applies to original code and documentation authored
for this repository. It does not relicense third-party code, quoted material,
firmware, images, or other third-party assets. Existing copyright, license,
and attribution notices remain applicable.

## Reproduced shim source

`shim/shim.c` and `shim/atf_common.h` reproduce code from Gouda-percha's
[RAM-only boot guide](https://failedattempts.neocities.org/part3a).
Their headers record that provenance, and `scripts/get-shim-source.py`
verifies the upstream code blocks before adding local explanatory comments.

The reproduced code is excluded from this repository's MIT grant. No explicit
upstream license is recorded in these files; attribution alone does not grant
permission to reuse or redistribute that code. Check the original source and
obtain any necessary permission before doing so.

## Patches

The files in `patches/` contain changes to Linux kernel and NXP U-Boot sources,
including upstream context. They are excluded from this repository's MIT
grant. Consult the exact upstream source files and their applicable licenses
before using or distributing the patches or patched builds. This repository
does not replace or override those licenses.

## External software and local assets

LemonadeMirror, Linux, NXP U-Boot, imx-mkimage, UUU, and other dependencies
retain their own licenses. Downloading or building them through this
repository does not make them MIT-licensed.

The local, Git-ignored `vendor/`, `reference-images/`, and `build/` directories
may contain third-party source, firmware, images, or generated binaries.
These assets are not covered by this repository's MIT grant. Consult their
respective sources for license terms and redistribution permissions.
