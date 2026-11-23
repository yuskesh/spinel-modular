# tests/freestanding/lane-env.sh -- sourced by every lane script, after it sets
# HERE to its own directory.
# It holds the lanes' tool defaults in one place.
# Nothing here has a home-directory default: a tool this repository does not
# build is named by the caller or the lane stops.
#
#   LLVM_PREFIX            the official LLVM 23.1.1 (docs/building.md); required
#   ZEPHYR_BASE            a Zephyr v4.4.2 tree; required by the device lanes
#   ZEPHYR_SDK_INSTALL_DIR the Zephyr SDK 1.0.1; required by the device lanes.
#                          Only a HINT to Zephyr's CMake: the lanes print the
#                          toolchain Zephyr actually found, and that is the one used.
#   WASI_BUILTINS          compiler-rt builtins for wasm32-unknown-wasip1; required
#                          by the wasm32 lanes (the LLVM release ships none)
#   WASI_SYSROOT           a wasi-libc sysroot; required by wasm (the wasip1
#                          reactor link)
#   NODE                   node, for the wasm32 lanes (default: node on PATH)
#   WRANGLER               wrangler, for wasm/run_worker.sh (default: on PATH)
#   BAREMETAL_BUILTINS     compiler-rt builtins for Cortex-M33 (thumbv8m.main, soft
#                          float), built from LLVM 23.1.1; required by bare
#                          (docs/toolchains/compiler-rt-23.1.1)
#   QEMU_ARM               qemu-system-arm with mps2-an521, for bare (default:
#                          on PATH; not the Zephyr SDK's)
#   FS_WORK                where lanes write (default: $TMPDIR/spinel-freestanding)
#
# Each lane writes under OUT, which is $FS_WORK/<lane> and is never taken from
# the environment: the lanes remove it, and OUT is a name callers export.

REPO=$(cd -- "$HERE/../../.." && pwd)
: "${LLVM_PREFIX:?set LLVM_PREFIX to the official LLVM 23.1.1 (docs/building.md)}"
CLANG=${CLANG:-$LLVM_PREFIX/bin/clang}
NM=${NM:-$LLVM_PREFIX/bin/llvm-nm}
WASM_LD=${WASM_LD:-$LLVM_PREFIX/bin/wasm-ld}
NODE=${NODE:-node}
# FSEMIT is the native emitter, spinel-fs-emit, which accepts
# `--freestanding --profile` (its "product spelling") as well as its own
# options.
. "$REPO/tests/freestanding/stamps.sh"
UNDEF=${UNDEF:-$FSCHECK}
FSDIR=$REPO/tools/freestanding
LANE=$(basename -- "$HERE")
# Built from this tree's source, or the lane stops here, before it writes
# anything (stamps.sh).
fs_stamps || { echo "$LANE: the native tools are not this tree's build (above); rebuild them" >&2; exit 2; }
OUT=${FS_WORK:-${TMPDIR:-/tmp}/spinel-freestanding}/$LANE
. "$HERE/../workdir.sh"
# Created marked, so a later build_all.sh may empty it.
[ -e "$OUT" ] || fs_fresh_workdir "$OUT"
# RES holds the lane's tables, consoles and generated headers. Writing them
# generated headers). Writing it here keeps the source tree clean.
RES=${RES:-$OUT/results}
for t in "$FSEMIT" "$FSCHECK" "$CLANG" "$NM"; do
  [ -x "$t" ] || { echo "$LANE: no executable at $t" >&2; exit 2; }
done

need_zephyr() {
  : "${ZEPHYR_BASE:?set ZEPHYR_BASE to a Zephyr v4.4.2 tree}"
  : "${ZEPHYR_SDK_INSTALL_DIR:?set ZEPHYR_SDK_INSTALL_DIR to the Zephyr SDK 1.0.1}"
  export ZEPHYR_BASE ZEPHYR_SDK_INSTALL_DIR
  export ZEPHYR_TOOLCHAIN_VARIANT=${ZEPHYR_TOOLCHAIN_VARIANT:-zephyr}
  WEST=${WEST:-west}
  command -v "$WEST" >/dev/null 2>&1 || { echo "$LANE: no west on PATH" >&2; exit 2; }
}
need_baremetal() {
  if [ -z "${BAREMETAL_BUILTINS:-}" ]; then
    echo "$LANE: set BAREMETAL_BUILTINS to compiler-rt's libclang_rt.builtins-armv8m.main.a (docs/toolchains/compiler-rt-23.1.1)" >&2
    exit 2
  fi
  [ -f "$BAREMETAL_BUILTINS" ] || { echo "$LANE: no file at BAREMETAL_BUILTINS=$BAREMETAL_BUILTINS" >&2; exit 2; }
  QEMU_ARM=${QEMU_ARM:-qemu-system-arm}
  command -v "$QEMU_ARM" >/dev/null 2>&1 || { echo "$LANE: no QEMU at QEMU_ARM=$QEMU_ARM" >&2; exit 2; }
}
need_wasm() {
  : "${WASI_BUILTINS:?set WASI_BUILTINS to libclang_rt.builtins.a for wasm32-unknown-wasip1}"
  [ -f "$WASI_BUILTINS" ] || { echo "$LANE: no file at WASI_BUILTINS=$WASI_BUILTINS" >&2; exit 2; }
  [ -x "$WASM_LD" ] || { echo "$LANE: no wasm-ld at $WASM_LD" >&2; exit 2; }
  command -v "$NODE" >/dev/null 2>&1 || { echo "$LANE: no node ('$NODE')" >&2; exit 2; }
}
