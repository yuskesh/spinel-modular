#!/bin/sh
#
# tests/bare-full/run.sh -- full, the hosted runtime with its collector, on a
# Cortex-M33 with no RTOS, under QEMU's mps2-an521.
#
#   sh tests/bare-full/run.sh
#
# Needs LLVM_PREFIX, BAREMETAL_PICOLIBC and BAREMETAL_BUILTINS (see
# tools/bare-full/README.md), qemu-system-arm and vendor/spinel built.
#
# 1. the runtime is compiled for the target once, and each program in
#    programs/ with a .out is built, run, and must print exactly its .out
#    (written by hand) and exit 0; gc.rb must also have collected;
# 2. oom.rb keeps everything it allocates: with a 64 KB heap it must stop
#    with the runtime's out-of-memory message and exit 1, not fault or hang;
# 3. every input in each link map is one of the program's own objects, the
#    runtime archive, picolibc's libc.a or compiler-rt's builtins, and the
#    loaded image does not name this checkout or the work directory (the
#    runtime's assertions keep __FILE__);
# 4. controls: a copy of basics.out with one planted wrong line must be
#    reported as different, and the input check with libc.a left out of its
#    allowed list must reject the same map, and a copy of the image with this
#    checkout's path appended must fail the path check.
#
# Exit 0 when everything passed, 1 on any failure, 2 when skipped. Nothing
# here runs another implementation.
set -u

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HERE="$REPO/tests/bare-full"
DRIVER="$REPO/tools/bare-full/spinel-bare-full"
RUBY="${RUBY:-ruby}"
QEMU="${QEMU:-qemu-system-arm}"
LIMIT="${BARE_FULL_TIMEOUT:-60}"

pass=0
fail=0
ok() { pass=$((pass + 1)); echo "PASS  $1"; }
ng() { fail=$((fail + 1)); echo "FAIL  $1"; }

for v in LLVM_PREFIX BAREMETAL_PICOLIBC BAREMETAL_BUILTINS; do
  eval "val=\${$v:-}"
  if [ -z "$val" ]; then
    echo "SKIP  bare-full: $v is not set"
    exit 2
  fi
done
if ! command -v "$QEMU" >/dev/null 2>&1; then
  echo "SKIP  bare-full: no $QEMU"
  exit 2
fi

# The link map names each object by the path the driver was given, and part 3
# compares those names with paths made from $T, so $T must not hold a doubled
# slash: macOS's TMPDIR ends in one.
TMP=${TMPDIR:-/tmp}
T=$(mktemp -d "${TMP%/}/bare-full-test.XXXXXX")
trap 'rm -rf "$T"' EXIT

# run_elf ELF LOG: boot ELF and wait until it prints its EXIT or FATAL line;
# _exit loops forever, so QEMU is stopped here
run_elf() {
  "$QEMU" -machine mps2-an521 -cpu cortex-m33 -m 16 -display none \
    -monitor none -serial "file:$2" -kernel "$1" >/dev/null 2>&1 &
  qpid=$!
  n=0
  while [ "$n" -lt "$LIMIT" ]; do
    grep -qE '^BAREFULL	(EXIT|FATAL)' "$2" 2>/dev/null && break
    sleep 1
    n=$((n + 1))
  done
  kill "$qpid" 2>/dev/null
  wait "$qpid" 2>/dev/null
  grep -qE '^BAREFULL	(EXIT|FATAL)' "$2" 2>/dev/null
}

# the program's own output: everything that is not a BAREFULL line
program_output() { grep -v '^BAREFULL	' "$1"; }
status_of() { sed -n 's/^BAREFULL	EXIT	//p' "$1"; }
collections_of() { sed -n 's/^BAREFULL	GC	//p' "$1"; }

# check_inputs MAP ALLOWED...: every object or archive the map names starts
# with one of ALLOWED
check_inputs() {
  map=$1
  shift
  "$RUBY" -e '
    map, *allowed = ARGV
    inputs = File.read(map).scan(/(\S+\.(?:o|a))(?:\([^)]*\))?:\(/).flatten.uniq
    abort "no inputs in #{map}" if inputs.empty?
    bad = inputs.reject { |i| allowed.any? { |a| i.start_with?(a) } }
    abort "inputs from elsewhere: #{bad.join(" ")}" unless bad.empty?
  ' "$map" "$@"
}

RT="$T/rt/libspinel_rt_bare.a"
if "$RUBY" "$DRIVER" runtime "$T/rt" >"$T/runtime.log" 2>&1; then
  ok "runtime: compiled for the target"
else
  tail -20 "$T/runtime.log"
  ng "runtime: compiled for the target"
  echo "bare-full: $pass passed, $fail failed"
  exit 1
fi

build() { # build NAME ELF [driver options]
  name=$1
  elf=$2
  shift 2
  "$RUBY" "$DRIVER" build --runtime "$RT" "$@" "$HERE/programs/$name.rb" "$elf" \
    >"$elf.build.log" 2>&1 || { tail -20 "$elf.build.log"; return 1; }
}

# no_paths BIN: BIN is not empty and names neither this checkout nor $T
no_paths() { [ -s "$1" ] && ! grep -aqF -e "$REPO" -e "$T" "$1"; }

allowed_all() { echo "$1.d/ $RT $BAREMETAL_PICOLIBC/lib/libc.a $BAREMETAL_BUILTINS"; }

# 1 and 3: the programs with expected output
for rb in "$HERE"/programs/*.rb; do
  name=$(basename "$rb" .rb)
  [ -f "$HERE/programs/$name.out" ] || continue
  elf="$T/$name.elf"
  if ! build "$name" "$elf"; then
    ng "$name: builds"
    continue
  fi
  if ! run_elf "$elf" "$T/$name.log"; then
    ng "$name: reached exit within ${LIMIT}s"
    continue
  fi
  if program_output "$T/$name.log" | diff - "$HERE/programs/$name.out" >"$T/$name.diff"; then
    ok "$name: prints its expected output"
  else
    head -20 "$T/$name.diff"
    ng "$name: prints its expected output"
  fi
  st=$(status_of "$T/$name.log")
  [ "$st" = 0 ] && ok "$name: exits 0" || ng "$name: exits 0 (got '${st:-a fault}')"
  if [ "$name" = gc ]; then
    gcs=$(collections_of "$T/$name.log")
    [ "${gcs:-0}" -ge 1 ] && ok "gc: collected ($gcs times)" || ng "gc: collected (got '${gcs:-none}')"
  fi
  # shellcheck disable=SC2046
  if check_inputs "$elf.map" $(allowed_all "$elf") 2>"$T/$name.inputs"; then
    ok "$name: links only the runtime, picolibc, the builtins and its own objects"
  else
    cat "$T/$name.inputs"
    ng "$name: links only the runtime, picolibc, the builtins and its own objects"
  fi
  "$LLVM_PREFIX/bin/llvm-objcopy" -O binary "$elf" "$elf.bin"
  if no_paths "$elf.bin"; then
    ok "$name: the loaded image names neither this checkout nor the work directory"
  else
    ng "$name: the loaded image names neither this checkout nor the work directory"
  fi
done

# 2: out of memory with a 64 KB heap
elf="$T/oom.elf"
if build oom "$elf" --heap-kb 64 && run_elf "$elf" "$T/oom.log"; then
  if grep -qx 'unhandled exception: out of memory' "$T/oom.log" && [ "$(status_of "$T/oom.log")" = 1 ]; then
    ok "oom: a 64 KB heap stops with the out-of-memory message and exit 1"
  else
    tail -5 "$T/oom.log"
    ng "oom: a 64 KB heap stops with the out-of-memory message and exit 1"
  fi
else
  ng "oom: builds and reaches exit within ${LIMIT}s"
fi

# 4: controls
if [ -f "$T/basics.log" ]; then
  sed '3s/.*/1025/' "$HERE/programs/basics.out" >"$T/basics.planted"
  if cmp -s "$HERE/programs/basics.out" "$T/basics.planted"; then
    ng "control: the planted line changed basics.out"
  elif program_output "$T/basics.log" | diff - "$T/basics.planted" >/dev/null; then
    ng "control: a planted wrong expectation is reported as different"
  else
    ok "control: a planted wrong expectation is reported as different"
  fi
  elf="$T/basics.elf"
  # shellcheck disable=SC2086
  if check_inputs "$elf.map" "$elf.d/" "$RT" "$BAREMETAL_BUILTINS" 2>/dev/null; then
    ng "control: the input check rejects libc.a when it is not allowed"
  else
    ok "control: the input check rejects libc.a when it is not allowed"
  fi
  { cat "$elf.bin"; printf '%s/vendor/spinel/lib/sp_bigint.c' "$REPO"; } >"$T/planted.bin"
  if no_paths "$T/planted.bin"; then
    ng "control: the path check finds this checkout's path planted in the image"
  else
    ok "control: the path check finds this checkout's path planted in the image"
  fi
else
  ng "controls: basics did not run"
fi

echo "bare-full: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
