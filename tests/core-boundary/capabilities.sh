#!/bin/sh
#
# tests/core-boundary/capabilities.sh -- scalar entries across the CORE
# boundary: 32-bit wrapping and masking, truncating division, and Q24.8
# multiplication and clamped division.
#
#   KERNEL=<spinel-core-kernel> tests/core-boundary/capabilities.sh
#
# Three lanes:
#
#   1. the kernels. Each entry under fixtures/capabilities/src is built as a
#      CORE object and called from C.
#   2. the cases. Every row of cases.tsv is run, and the kernel must give the
#      answer the row records. The answers were worked out by hand from each
#      entry's definition; no other implementation is run.
#   3. mutation controls. One point of one source is changed (mutations.tsv),
#      and the kernel built from it must give a different answer for at least
#      one case. A control that changed nothing would mean the table cannot
#      see that part of the computation.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HERE="$ROOT/tests/core-boundary"
FIX="$HERE/fixtures/capabilities"
KERNEL="${KERNEL:-$ROOT/tools/mlir/native/build/bin/spinel-core-kernel}"
. "$ROOT/tools/test/source-stamp.sh"
source_stamp kernel "$KERNEL"
CC_BIN="${CC:-${LLVM_PREFIX:-/opt/llvm-23.1.1}/bin/clang}"
RUBY="${RUBY:-ruby}"

die() { echo "capabilities: $*" >&2; exit 1; }
[ -f "$FIX/cases.tsv" ] || die "no case table at $FIX/cases.tsv"
[ -f "$FIX/mutations.tsv" ] || die "no mutation table at $FIX/mutations.tsv"
[ -x "$KERNEL" ] || die "no spinel-core-kernel at $KERNEL (build it first)"
[ -x "$CC_BIN" ] || die "no C compiler at $CC_BIN"
command -v "$RUBY" >/dev/null 2>&1 || die "no ruby at '$RUBY'"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/core-capabilities.XXXXXX")
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

# run_cases <harness> <out>: "<id>\t<answer>" per case; the count is returned
# by the caller reading the file.
run_cases() {
  : > "$2"
  while IFS="$TAB" read -r id entry args want; do
    case "$id" in \#*|"") continue ;; esac
    set +e
    got=$("$1" "$entry" $(echo "$args" | tr ',' ' ') 2>&1); rc=$?
    set -e
    [ "$rc" -eq 0 ] || got="exit $rc"
    printf '%s\t%s\n' "$id" "$got" >> "$2"
  done < "$FIX/cases.tsv"
}

echo "== the kernels build =="
if build_all "$FIX" "$WORK/base"; then
  n_k=$(ls "$WORK"/base/*.o | wc -l | tr -d ' ')
  echo "  pass $n_k kernel(s) and the harness built"; pass=$((pass + 1))
else
  echo "  FAIL a kernel or the harness did not build:"
  cat "$WORK"/base/*.build "$WORK/base/harness.log" 2>/dev/null | sed 's/^/      /' | head -8
  echo "capabilities: $((pass + fail + 1)) checked, $pass pass, $((fail + 1)) fail"
  exit 1
fi

echo "== each case gives the recorded answer =="
run_cases "$WORK/base/harness" "$WORK/base.tsv"
ran=0
while IFS="$TAB" read -r id entry args want; do
  case "$id" in \#*|"") continue ;; esac
  ran=$((ran + 1))
  [ -n "$want" ] || { echo "  FAIL $id records no answer"; fail=$((fail + 1)); continue; }
  got=$(awk -F"$TAB" -v k="$id" '$1 == k { print $2 }' "$WORK/base.tsv")
  if [ "$got" = "$want" ]; then
    echo "  pass $id = $got"; pass=$((pass + 1))
  else
    echo "  FAIL $id: the table says $want, the kernel says $got"; fail=$((fail + 1))
  fi
done < "$FIX/cases.tsv"
[ "$ran" -gt 0 ] || die "the case table is empty"
# Every entry has at least one case, or an entry could be built and never asked.
for f in "$FIX"/src/*.contract; do
  stem=$(basename "$f" .contract)
  if awk -F"$TAB" -v e="$stem" '!/^#/ && $2 == e { n = 1 } END { exit !n }' "$FIX/cases.tsv"; then
    :
  else
    echo "  FAIL $stem has no case"; fail=$((fail + 1))
  fi
done

echo "== mutation controls =="
n_mut=0
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
    # A change the compiler refuses is not a control of the table.
    echo "  FAIL $id: the changed source did not build"; fail=$((fail + 1)); continue
  fi
  run_cases "$m/out/harness" "$m/answers.tsv"
  if cmp -s "$WORK/base.tsv" "$m/answers.tsv"; then
    echo "  FAIL $id: every case still gives the same answer ($what)"; fail=$((fail + 1))
  else
    echo "  pass $id changes an answer ($what)"; pass=$((pass + 1))
  fi
done < "$FIX/mutations.tsv"
[ "$n_mut" -gt 0 ] || die "the mutation table is empty"

echo "capabilities: $((pass + fail)) checked, $pass pass, $fail fail"
[ "$fail" -eq 0 ] || exit 1
