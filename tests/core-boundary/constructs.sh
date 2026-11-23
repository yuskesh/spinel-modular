#!/bin/sh
#
# tests/core-boundary/constructs.sh -- what the checked subset admits and
# what it refuses, one construct at a time.
#
#   KERNEL=<spinel-core-kernel> tests/core-boundary/constructs.sh
#
# Two lanes:
#
#   1. constructs. Each row of fixtures/constructs/constructs.tsv is a probe
#      the checker is asked about, and it must answer what the row says --
#      `admitted`, or the diagnostic category the row names. Rows exist for
#      what IS admitted as well as for what is not: a table of refusals alone
#      would say nothing about whether the checker still takes what it
#      should.
#   2. nothing quietly dropped. The construct count is declared here, so the
#      table cannot shrink without this file changing.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
FIX="$ROOT/tests/core-boundary/fixtures/constructs"
KERNEL="${KERNEL:-$ROOT/tools/mlir/native/build/bin/spinel-core-kernel}"
. "${ROOT:-$root}/tools/test/source-stamp.sh"
source_stamp kernel "$KERNEL"
CC_BIN="${CC:-${LLVM_PREFIX:-/opt/llvm-23.1.1}/bin/clang}"
RUBY="${RUBY:-ruby}"

die() { echo "constructs: $*" >&2; exit 1; }
[ -f "$FIX/constructs.tsv" ] || die "no construct table at $FIX/constructs.tsv"
[ -x "$KERNEL" ] || die "no spinel-core-kernel at $KERNEL (build it first)"
[ -x "$CC_BIN" ] || die "no C compiler at $CC_BIN"
command -v "$RUBY" >/dev/null 2>&1 || die "no ruby at '$RUBY'"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/core-constructs.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM
pass=0; fail=0
TAB=$(printf '\t')

echo "== the constructs answer what the table says they do =="
mkdir -p "$WORK/src"
n_row=0
while IFS="$TAB" read -r id shape verdict what; do
  case "$id" in \#*|"") continue ;; esac
  n_row=$((n_row + 1))
  case "$shape" in
    narrow)
      # The body between this row's marker and the next.
      awk -v want="--- $id" '
        $0 == want { on = 1; next }
        /^--- / { on = 0 }
        on { print }
      ' "$FIX/src/probes.rb" > "$WORK/src/$id.rb"
      if [ ! -s "$WORK/src/$id.rb" ]; then
        echo "  FAIL $id has no body in src/probes.rb"; fail=$((fail + 1)); continue
      fi
      { echo "core-contract 1"; echo "root src/$id.rb"; echo "entry probe"
        echo "result i64"; echo "param a scalar i64"; echo "param b scalar i64"
        echo "param buf buffer i32 inout count n_buf"; echo "param n_buf scalar u64"
      } > "$WORK/src/$id.contract"
      ;;
    generated)
      # The row whose point is its width: thirty declared buffers, the shape of
      # a record kept as one array per field.
      "$RUBY" -e '
        n = 30
        names = (0...n).flat_map { |i| ["a#{i}", "n_a#{i}"] }
        File.write(ARGV[0] + ".rb", "def probe(" + names.join(", ") + ")\n  a0[0] = a1[0]\n  0\nend\n")
        c = ["core-contract 1", "root src/" + File.basename(ARGV[0]) + ".rb", "entry probe", "result i64"]
        (0...n).each { |i| c << "param a#{i} buffer i32 inout count n_a#{i}"; c << "param n_a#{i} scalar u64" }
        File.write(ARGV[0] + ".contract", c.join("\n") + "\n")
      ' "$WORK/src/$id"
      ;;
    *) echo "  FAIL $id has shape $shape, which is not narrow or generated"
       fail=$((fail + 1)); continue ;;
  esac

  set +e
  out=$("$KERNEL" "$WORK/src/$id.contract" --root "$WORK" -o /dev/null --header /dev/null \
        --clang "$CC_BIN" 2>&1)
  rc=$?
  set -e
  if [ "$verdict" = admitted ]; then
    if [ "$rc" -eq 0 ]; then
      echo "  pass $id is admitted ($what)"; pass=$((pass + 1))
    else
      echo "  FAIL $id should be admitted ($what) but:"
      printf '%s\n' "$out" | sed 's/^/      /' | head -2; fail=$((fail + 1))
    fi
  elif [ "$rc" -eq 0 ]; then
    echo "  FAIL $id built; the table says it is refused as $verdict ($what)"
    fail=$((fail + 1))
  elif printf '%s' "$out" | grep -q ": $verdict: "; then
    echo "  pass $id is refused as $verdict ($what)"; pass=$((pass + 1))
  else
    echo "  FAIL $id is refused, but not as $verdict:"
    printf '%s\n' "$out" | sed 's/^/      /' | head -2; fail=$((fail + 1))
  fi
done < "$FIX/constructs.tsv"
[ "$n_row" -gt 0 ] || die "the construct table is empty"

# Every body has a row, not only every row a body.
for m in $(grep '^--- ' "$FIX/src/probes.rb" | sed 's/^--- //'); do
  if ! grep -q "^$m$TAB" "$FIX/constructs.tsv"; then
    echo "  FAIL $m has a body with no row in the table"; fail=$((fail + 1))
  fi
done
dup=$(awk -F"$TAB" '!/^#/ && NF { print $1 }' "$FIX/constructs.tsv" | sort | uniq -d)
[ -z "$dup" ] || { echo "  FAIL the construct table names these twice: $dup"; fail=$((fail + 1)); }

echo "== nothing was quietly dropped =="
# The construct table can shrink without a check failing, so its size is
# declared here and compared. A reset of this kind is only
# safe when the declaration is in the file the change would have to touch.
EXPECT_CONSTRUCTS=28
if [ "$n_row" -ne "$EXPECT_CONSTRUCTS" ]; then
  echo "  FAIL $n_row construct(s) in the table, and this lane expects $EXPECT_CONSTRUCTS"
  fail=$((fail + 1))
else
  echo "  pass all $EXPECT_CONSTRUCTS constructs are still probed"
  pass=$((pass + 1))
fi

echo "constructs: $((pass + fail)) checked, $pass pass, $fail fail, $n_row construct(s) probed"
[ "$fail" -eq 0 ] || exit 1
