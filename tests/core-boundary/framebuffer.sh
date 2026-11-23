#!/bin/sh
#
# tests/core-boundary/framebuffer.sh -- kernels that draw into a screen Full
# lends: a column from a repeating pattern, a row sampled from a tile, and a
# column rewritten from its neighbouring rows. The answer is a SCREEN, so the
# comparison is every byte of it, including the bytes no job should touch.
#
#   KERNEL=<spinel-core-kernel> tests/core-boundary/framebuffer.sh
#
# Four lanes:
#
#   1. the kernels. Each entry under fixtures/framebuffer/src is built as a
#      CORE object.
#   2. the scene. fixtures/framebuffer/scene.tsv lists the tables, the jobs
#      and the screen they must leave. The C harness draws nothing: it
#      parses, calls and compares. Run backwards, the same jobs must leave a
#      DIFFERENT screen, or their order would not be observed. The numbers
#      were worked out by hand from the definitions; no other implementation
#      is run.
#   3. the status ABI. An index off either end of the screen or of a table,
#      and arithmetic past 64 bits, each answer a status, and each edge has
#      the case just inside it. A refusal's count of pixels already drawn is
#      taken from the screen.
#   4. mutation controls. One point of one source is changed (mutations.tsv)
#      and the run mode must fail over the same scene.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
FIX="$ROOT/tests/core-boundary/fixtures/framebuffer"
KERNEL="${KERNEL:-$ROOT/tools/mlir/native/build/bin/spinel-core-kernel}"
. "$ROOT/tools/test/source-stamp.sh"
source_stamp kernel "$KERNEL"
CC_BIN="${CC:-${LLVM_PREFIX:-/opt/llvm-23.1.1}/bin/clang}"
RUBY="${RUBY:-ruby}"

die() { echo "framebuffer: $*" >&2; exit 1; }
[ -f "$FIX/scene.tsv" ] || die "no scene at $FIX/scene.tsv"
[ -f "$FIX/mutations.tsv" ] || die "no mutation table at $FIX/mutations.tsv"
[ -x "$KERNEL" ] || die "no spinel-core-kernel at $KERNEL (build it first)"
[ -x "$CC_BIN" ] || die "no C compiler at $CC_BIN"
command -v "$RUBY" >/dev/null 2>&1 || die "no ruby at '$RUBY'"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/core-framebuffer.XXXXXX")
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
  echo "framebuffer: $((pass + fail + 1)) checked, $pass pass, $((fail + 1)) fail"
  exit 1
fi

echo "== the scene, its order and the status ABI =="
for mode in run reverse refuse; do
  set +e
  out=$("$WORK/base/harness" "$FIX/scene.tsv" "$mode" 2>&1); rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "  pass $out"; pass=$((pass + 1))
  else
    echo "  FAIL $mode: $out"; fail=$((fail + 1))
  fi
done

echo "== a scene that would pass for the wrong reason is refused =="
# The harness's own guards, each shown to fire.
# guard <name> <mode> <the message wanted>: the scene is $WORK/guard-<name>.tsv.
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
awk -F"$TAB" '!($1 == "job" && $2 == "smear")' "$FIX/scene.tsv" > "$WORK/guard-a-kernel-never-reached.tsv"
guard a-kernel-never-reached run "never reaches one of the kernels"
sed "s/^screen$TAB.*/screen${TAB}0,0,0,0,0,0/" "$FIX/scene.tsv" > "$WORK/guard-a-blank-screen.tsv"
guard a-blank-screen run "the expected screen is blank"
awk -F"$TAB" '!($1 == "check" && $12 == "2")' "$FIX/scene.tsv" > "$WORK/guard-no-arithmetic-check.tsv"
guard no-arithmetic-check refuse "never refuse with both statuses"
awk -F"$TAB" '!($1 == "check" && $12 == "0")' "$FIX/scene.tsv" > "$WORK/guard-no-accepted-check.tsv"
guard no-accepted-check refuse "no check is accepted"
# A wrong number in the scene is seen: one expected pixel and one declared move.
sed "s/^screen${TAB}0,14,0,0,12,0\$/screen${TAB}0,14,0,0,13,0/" "$FIX/scene.tsv" > "$WORK/guard-a-wrong-pixel.tsv"
guard a-wrong-pixel run "the scene says 13"
awk -F"$TAB" -v OFS="$TAB" '$1 == "check" && $2 == "row-past-the-end" { $13 = 0 } { print }' "$FIX/scene.tsv" \
  > "$WORK/guard-a-wrong-move.tsv"
guard a-wrong-move refuse "changed 1 cell(s), and declares 0"

echo "== mutation controls =="
n_mut=0
mode=run
while IFS="$TAB" read -r id file old new what; do
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
  "$m/out/harness" "$FIX/scene.tsv" "$mode" > "$m/out.txt" 2>&1; rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "  FAIL $id: the $mode mode still passes ($what)"; fail=$((fail + 1))
  else
    echo "  pass $id fails the $mode mode ($what)"; pass=$((pass + 1))
  fi
done < "$FIX/mutations.tsv"
[ "$n_mut" -gt 0 ] || die "the mutation table is empty"

echo "framebuffer: $((pass + fail)) checked, $pass pass, $fail fail"
[ "$fail" -eq 0 ] || exit 1
