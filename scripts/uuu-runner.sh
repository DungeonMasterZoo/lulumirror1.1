#!/bin/sh
set -eu
libdir="$(dirname $0)/../.pixi/envs/default/lib"
for library in libssl.3.dylib libcrypto.3.dylib libusb-1.0.0.dylib libzstd.1.dylib libtinyxml2.11.dylib; do
  if [ ! -f "$libdir/$library" ]; then
    echo "Missing $library; run mise run setup" >&2
    exit 1
  fi
done
if [ "${UUU_TRACE_LIBS:-0}" = 1 ]; then
  exec env DYLD_PRINT_LIBRARIES=1 DYLD_LIBRARY_PATH="$libdir" uuu "$@"
fi
exec env DYLD_LIBRARY_PATH="$libdir" uuu "$@"
