#!/bin/sh
# tests/freestanding/run.sh -- every freestanding target lane, in one run.
#
# The lanes: ints (QEMU Cortex-M33 and RV32), wasm (wasm32 under node and
# workerd), buffers (Float and buffers on M33, RV32 and wasm32), externs (platform
# externs on all three), the profile reader, and bare: ints's kernel on the
# bare Cortex-M33 with no RTOS; and ints and bare on the FRDM-MCXN947 board.
# A script's exit status is its verdict, and summary.rb counts the rows of
# the tables it wrote.
#
# Requires what tests/freestanding/lane-env.sh names: LLVM_PREFIX,
# ZEPHYR_BASE, ZEPHYR_SDK_INSTALL_DIR, WASI_BUILTINS, WASI_SYSROOT, west, node
# and wrangler on PATH, tools/contract/build.sh (spinel-typedump), the native
# build (tools/mlir/native/build.sh), and for bare
# BAREMETAL_BUILTINS and QEMU_ARM. A lane that cannot
# start for want of one of them fails; nothing here is skipped, except the
# board lanes (ints's run_frdm.sh, and bare-frdm after its image checks),
# which need hardware and are NOT RUN without FRDM_HOST (exit 3; a failure
# under REQUIRE_ALL=1).
#
# No lane here compares with another implementation's behaviour (README.md).
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RUBY=${RUBY:-ruby}
FS_WORK=${FS_WORK:-${TMPDIR:-/tmp}/spinel-freestanding}
export FS_WORK

# The native tools every lane uses, held to this tree before any lane runs
# (stamps.sh): a stale build is refused here, by name, once.
REPO=$(CDPATH= cd -- "$HERE/../.." && pwd)
. "$HERE/stamps.sh"
fs_stamps || { echo "run: the native tools are not this tree's build (above); no lane was run" >&2; exit 1; }

failed=""
t_all=$(date +%s)
lane() {  # name script...
  n=$1; shift
  t0=$(date +%s); rc=0; notrun=""
  mkdir -p "$FS_WORK"
  for s in "$@"; do
    bash "$HERE/$n/$s" > "$FS_WORK/$n.$s.log" 2>&1
    src=$?
    # Exit 3 is a lane that needs hardware and found none (NOT RUN; a failure
    # under REQUIRE_ALL=1, where the script exits 1 instead). The scripts
    # after it need what it would have made, so they are not run either.
    if [ "$src" = 3 ]; then
      notrun=$(sed -n "s|^$n: NOT RUN: ||p" "$FS_WORK/$n.$s.log" | tail -1)
      break
    elif [ "$src" != 0 ]; then
      rc=1; echo "  $n/$s failed; last lines of $FS_WORK/$n.$s.log:"
      tail -5 "$FS_WORK/$n.$s.log" | sed 's/^/    /'
    fi
  done
  counts=$("$RUBY" "$HERE/summary.rb" "$FS_WORK/$n/results") || rc=1
  echo "$n: $counts${notrun:+; NOT RUN: $notrun} [rc $rc, $(( $(date +%s) - t0 )) s]"
  [ "$rc" = 0 ] || failed="$failed $n"
}

lane ints build_all.sh run_gates.sh run_reject.sh run_wide.sh
# ints on the FRDM-MCXN947 board, through LinkServer on a Linux host. It needs
# that host and the board (FRDM_HOST, README.md), so without them it is NOT RUN
# (exit 3) and the run goes on; REQUIRE_ALL=1 makes that a failure.
t0=$(date +%s)
sh "$HERE/ints/run_frdm.sh" > "$FS_WORK/ints.run_frdm.sh.log" 2>&1
rc=$?
if [ "$rc" = 3 ]; then
  echo "ints-frdm: NOT RUN: $(sed -n 's|^ints/frdm: NOT RUN: ||p' "$FS_WORK/ints.run_frdm.sh.log") [$(( $(date +%s) - t0 )) s]"
else
  if [ "$rc" != 0 ]; then
    echo "  ints/run_frdm.sh failed; last lines of $FS_WORK/ints.run_frdm.sh.log:"
    tail -5 "$FS_WORK/ints.run_frdm.sh.log" | sed 's/^/    /'
  fi
  counts=$("$RUBY" "$HERE/summary.rb" "$FS_WORK/ints/frdm/results") || rc=1
  echo "ints-frdm: $counts [rc $rc, $(( $(date +%s) - t0 )) s]"
  [ "$rc" = 0 ] || failed="$failed ints-frdm"
fi
# bare compares its rows with ints's Zephyr run, so it comes after it.
lane bare build_all.sh run_gates.sh run_join.sh
# bare on the FRDM-MCXN947 board, compared with bare's QEMU run. Its image
# checks need no board; the board part is NOT RUN without FRDM_HOST.
lane bare-frdm build_all.sh run_gates.sh run_join.sh
lane wasm build.sh run_gates.sh run_worker.sh
lane buffers build_all.sh run_gates.sh run_reject.sh
lane externs build_all.sh run_extern_check.sh run_gates.sh run_reject.sh

if "$RUBY" "$HERE/int-width/run.rb" > "$FS_WORK/int-width.log" 2>&1; then rc=0; else rc=1; fi
echo "int-width: $(tail -1 "$FS_WORK/int-width.log") [rc $rc]"
[ "$rc" = 0 ] || failed="$failed int-width"

t0=$(date +%s)
if "$RUBY" "$HERE/profiles/test_profile_reader.rb" > "$FS_WORK/profiles.log" 2>&1; then rc=0; else rc=1; fi
echo "profiles: $(grep -E '^[0-9]+ runs' "$FS_WORK/profiles.log") [rc $rc, $(( $(date +%s) - t0 )) s]"
[ "$rc" = 0 ] || failed="$failed profiles"

echo
echo "total wall: $(( $(date +%s) - t_all )) s"
if [ -n "$failed" ]; then echo "run: failed:$failed"; exit 1; fi
echo "run: every lane passed"
