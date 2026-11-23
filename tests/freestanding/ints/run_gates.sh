#!/usr/bin/env bash
# The `ints` lane's device runs. build_all.sh first.
#
# Not run here: the differential join (host i64 C build vs MCU, gates.tsv). It
# compares with another implementation's behaviour, and this repository has
# no runner for it. What stays is that each board
# RAN every case to its END marker without a FATAL line (a count, not a value),
# and that the trap platform really stops.
#
# QEMU never exits, so each run stops at the console's terminator.
# The per-function size table is not produced; object and image sizes are.
#
# Writes, in $RES: ran.tsv, trap.tsv, size.tsv and the qemu_*.log consoles.
set -uo pipefail
HERE=$(cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/../lane-env.sh"
need_zephyr
SIZE="$LLVM_PREFIX/bin/llvm-size"
QEMU_TIMEOUT=${QEMU_TIMEOUT:-300}
mkdir -p "$RES"

run_qemu() {   # $1 = build tag, $2 = log, $3 = terminator regex
  local tag=$1 log=$2 term=$3
  echo "== qemu: $tag =="
  rm -f "$OUT/build_$tag/qemu.pid"
  ( "$WEST" build -d "$OUT/build_$tag" -t run > "$RES/$log" 2>&1 ) &
  local wpid=$!
  local i=0
  while [ $i -lt "$QEMU_TIMEOUT" ]; do
    grep -qE "$term" "$RES/$log" 2>/dev/null && break
    sleep 1; i=$(( i + 1 ))
  done
  if [ -f "$OUT/build_$tag/qemu.pid" ]; then
    kill "$(cat "$OUT/build_$tag/qemu.pid")" 2>/dev/null || true
  fi
  kill "$wpid" 2>/dev/null || true
  wait "$wpid" 2>/dev/null || true
  rm -f "$OUT/build_$tag/qemu.pid"
}
run_qemu m33      qemu_m33.log     'INTS	END'
run_qemu riscv32  qemu_riscv32.log 'INTS	END'
run_qemu m33panic qemu_panic.log   'PANIC|Halting|Faulting instruction'

# QEMU's serial console emits CRLF, so the trailing \r has to go.
extract() {  # $1 = log -> two-column TSV of case/result
  grep '^INTS	' "$1" | grep -v '	BEGIN	\|	END	\|	FATAL	' | cut -f2- | tr -d '\r'
}

# --- every case ran (the value join is the oracle) --------------------------
ncases=$(( $(wc -l < "$OUT/gen/expect.tsv") - 1 ))
{
printf 'target\tcases\trows\tend\tfatal\tverdict\n'
for t in m33 riscv32; do
  log="$RES/qemu_$t.log"
  rows=$(extract "$log" | sed '/^$/d' | wc -l | tr -d ' ')
  end=$(grep -c '^INTS	END' "$log" || true); fatal=$(grep -c '^INTS	FATAL' "$log" || true)
  if [ "$rows" = "$ncases" ] && [ "$end" -ge 1 ] && [ "$fatal" = 0 ]; then v=PASS; else v=FAIL; fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$t" "$ncases" "$rows" "$end" "$fatal" "$v"
done
} > "$RES/ran.tsv"

# --- 4. the trap platform --------------------------------------------------
# The harness build's spinel_trap longjmps so that all cases fit in one image.
# This build's spinel_trap does what a product would do, and the run has to STOP.
{
printf 'check\tresult\n'
# mulnarrow(46341, 46341) overflows the 32-bit body: code 1.
if grep -q '^INTS	TRAP	code=1' "$RES/qemu_panic.log"; then
  printf 'panic_trap_reached\tPASS\n'
else
  printf 'panic_trap_reached\tFAIL\n'
fi
if grep -q 'INTS	UNREACHABLE' "$RES/qemu_panic.log"; then
  printf 'panic_stops_execution\tFAIL (execution continued past the trap)\n'
else
  printf 'panic_stops_execution\tPASS\n'
fi
if grep -qi 'PANIC\|Halting system\|Faulting instruction' "$RES/qemu_panic.log"; then
  printf 'panic_reported_by_zephyr\tPASS\n'
else
  printf 'panic_reported_by_zephyr\tFAIL\n'
fi
} > "$RES/trap.tsv"

# --- 5. size (a record, not a check) ------------------------------------------
{
printf 'target\tkind\tname\tbytes\n'
for t in cortex-m33-zephyr riscv32-zephyr; do
  printf '%s\tobject\ttext\t%s\n' "$t" "$($SIZE "$OUT/gen/kern.$t.o" | awk 'NR==2{print $1}')"
done
for b in m33 m33panic riscv32; do
  if [ -f "$OUT/build_$b/zephyr/zephyr.elf" ]; then
    $SIZE "$OUT/build_$b/zephyr/zephyr.elf" \
      | awk -v b="$b" 'NR==2{printf "%s\timage\ttext\t%s\n%s\timage\tdata\t%s\n%s\timage\tbss\t%s\n", b,$1,b,$2,b,$3}'
  fi
done
} > "$RES/size.tsv"

cat "$RES/ran.tsv"; echo "---"; cat "$RES/trap.tsv"
rfails=$(grep -c 'FAIL' "$RES/ran.tsv" || true)
tfails=$(grep -c FAIL "$RES/trap.tsv" || true)
[ "$rfails" = 0 ] && [ "$tfails" = 0 ]
