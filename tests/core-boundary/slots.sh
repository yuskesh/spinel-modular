#!/bin/sh
#
# tests/core-boundary/slots.sh -- state kept in buffers Full lends: a pool of
# fixed capacity that hands slots out and takes them back, and a first-in
# first-out queue threaded through those slots, with reuse, removal from the
# middle and exhaustion.
#
#   KERNEL=<spinel-core-kernel> tests/core-boundary/slots.sh
#
# Four lanes:
#
#   1. the kernels. Each entry under fixtures/slots/src is built as a CORE
#      object.
#   2. the trace. fixtures/slots/trace.tsv lists operations, the answer each
#      must give and the cells the arrays must hold along the way. The C
#      harness models nothing: it parses, calls and compares. The numbers were
#      worked out by hand from the definitions; no other implementation is
#      run.
#   3. the status ABI. An index outside an array, a pool with nothing left, an
#      empty queue and a chain that closes on itself each answer a status, and
#      each edge has the case just inside it. A refusal's count of cells
#      already written is taken from the arrays.
#   4. mutation controls. One point of one source is changed (mutations.tsv)
#      and the named mode must fail over the same trace.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
FIX="$ROOT/tests/core-boundary/fixtures/slots"
KERNEL="${KERNEL:-$ROOT/tools/mlir/native/build/bin/spinel-core-kernel}"
. "$ROOT/tools/test/source-stamp.sh"
source_stamp kernel "$KERNEL"
CC_BIN="${CC:-${LLVM_PREFIX:-/opt/llvm-23.1.1}/bin/clang}"
RUBY="${RUBY:-ruby}"

die() { echo "slots: $*" >&2; exit 1; }
[ -f "$FIX/trace.tsv" ] || die "no trace at $FIX/trace.tsv"
[ -f "$FIX/mutations.tsv" ] || die "no mutation table at $FIX/mutations.tsv"
[ -x "$KERNEL" ] || die "no spinel-core-kernel at $KERNEL (build it first)"
[ -x "$CC_BIN" ] || die "no C compiler at $CC_BIN"
command -v "$RUBY" >/dev/null 2>&1 || die "no ruby at '$RUBY'"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/core-slots.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM
pass=0; fail=0
TAB=$(printf '\t')

# build_all <root> <outdir>: every contract's kernel, then the harness.
build_all() {
  mkdir -p "$2"
  for f in "$1"/src/*.contract; do
    stem=$(basename "$f" .contract)
    "$KERNEL" "$f" --root "$1" -o "$2/$stem.o" \
      --header "$2/spinel_core_$stem.h" --clang "$CC_BIN" > "$2/$stem.build" 2>&1 || return 1
  done
  "$CC_BIN" -std=c11 -Wall -Wextra -Werror -I"$2" "$FIX/harness.c" "$2"/*.o \
    -o "$2/harness" 2> "$2/harness.log"
}

echo "== the kernels build =="
if build_all "$FIX" "$WORK/base"; then
  echo "  pass $(ls "$WORK"/base/*.o | wc -l | tr -d ' ') kernel(s) and the harness built"
  pass=$((pass + 1))
else
  echo "  FAIL a kernel or the harness did not build:"
  cat "$WORK"/base/*.build "$WORK/base/harness.log" 2>/dev/null | sed 's/^/      /' | head -8
  echo "slots: $((pass + fail + 1)) checked, $pass pass, $((fail + 1)) fail"
  exit 1
fi

echo "== the trace and the status ABI =="
for mode in run refuse; do
  set +e
  out=$("$WORK/base/harness" "$FIX/trace.tsv" "$mode" 2>&1); rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "  pass $out"; pass=$((pass + 1))
  else
    echo "  FAIL $mode: $out"; fail=$((fail + 1))
  fi
done

echo "== a trace that would pass for the wrong reason is refused =="
# The harness's own guards, each shown to fire. Without them a trace with
# nothing in it, or checks that are all of one kind, would pass.
# guard <name> <mode> <the message wanted>: the trace is $WORK/guard-<name>.tsv.
# The caller writes that file first; a pipeline into this function would run
# it in a subshell and lose its count.
guard() {
  set +e
  out=$("$WORK/base/harness" "$WORK/guard-$1.tsv" "$2" 2>&1); rc=$?
  set -e
  if [ "$rc" -ne 0 ] && printf "%s" "$out" | grep -qF "$3"; then
    echo "  pass $1 is refused"; pass=$((pass + 1))
  else
    echo "  FAIL $1 was not refused as expected (rc $rc): $out"; fail=$((fail + 1))
  fi
}
grep -v "^expect$TAB" "$FIX/trace.tsv" > "$WORK/guard-no-expectation.tsv"
guard no-expectation run "no operation or no expectation"
printf "cap\t4\nop\tslot_take\t-\t-\t0\nexpect\tstate\t-1,1\n" > "$WORK/guard-a-kernel-never-reached.tsv"
guard a-kernel-never-reached run "never reaches one of the kernels"
awk -F"$TAB" "!(\$1 == \"check\" && \$7 == \"4\")" "$FIX/trace.tsv" > "$WORK/guard-no-capacity-check.tsv"
guard no-capacity-check refuse "never refuse with both statuses"
awk -F"$TAB" "!(\$1 == \"check\" && \$7 == \"0\")" "$FIX/trace.tsv" > "$WORK/guard-no-accepted-check.tsv"
guard no-accepted-check refuse "no check is accepted"
# A wrong number in the trace is seen: one expected cell and one declared move.
sed "s/^expect${TAB}q${TAB}1,1,1\$/expect${TAB}q${TAB}1,1,2/" "$FIX/trace.tsv" > "$WORK/guard-a-wrong-cell.tsv"
guard a-wrong-cell run "the trace says 2"
awk -F"$TAB" -v OFS="$TAB" "\$1 == \"check\" && \$2 == \"put-short-links\" { \$8 = 0 } { print }" "$FIX/trace.tsv" \
  > "$WORK/guard-a-wrong-move.tsv"
guard a-wrong-move refuse "changed 1 cell(s), and declares 0"

echo "== mutation controls =="
n_mut=0
while IFS="$TAB" read -r id file old new mode what; do
  case "$id" in \#*|"") continue ;; esac
  n_mut=$((n_mut + 1))
  m="$WORK/mut-$id"
  mkdir -p "$m"
  cp -R "$FIX/src" "$m/src"
  # Exactly one occurrence, so a row cannot change more than it says.
  if ! "$RUBY" -e '
      path, old, new = ARGV
      s = File.read(path)
      abort "#{s.scan(old).size} occurrence(s)" unless s.scan(old).size == 1
      File.write(path, s.sub(old) { new })' "$m/src/$file" "$old" "$new" 2> "$m/edit.err"; then
    echo "  FAIL $id: the text to change is not there exactly once ($(cat "$m/edit.err"))"
    fail=$((fail + 1)); continue
  fi
  if ! build_all "$m" "$m/out"; then
    echo "  FAIL $id: the changed source did not build"; fail=$((fail + 1)); continue
  fi
  set +e
  "$m/out/harness" "$FIX/trace.tsv" "$mode" > "$m/out.txt" 2>&1; rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "  FAIL $id: the $mode mode still passes ($what)"; fail=$((fail + 1))
  else
    echo "  pass $id fails the $mode mode ($what)"; pass=$((pass + 1))
  fi
done < "$FIX/mutations.tsv"
[ "$n_mut" -gt 0 ] || die "the mutation table is empty"

echo "slots: $((pass + fail)) checked, $pass pass, $fail fail"
[ "$fail" -eq 0 ] || exit 1
