#!/bin/sh
# Integer loops on the --core route: `while`, `until` and `x op= e` in an
# ordinary Ruby method, built with tools/core/spinel-core-build.
#
# Expectations are derived by hand from the programs in fixtures/loops; no
# CRuby or other runtime oracle runs here.
#
# What is checked:
#   - each admitted program prints the values derived for it, with the exit
#     status and standard error a checked failure gives (overflow, a zero
#     divisor) where the program reaches one;
#   - a loop that never ends is ended by SIGINT, as the hosted program is;
#   - the core object defines SYMBOL__pure when the method holds a loop, and
#     SYMBOL when it does not; the artifact gate refuses the other name;
#   - each form in fixtures/loops/refused is refused at build time, and the
#     output names the reason given for it below.
#
# usage: tests/native-core/loops.sh
#   SPINEL_CORE_BUILD  build directory holding bin/spinel-core-check and
#                      bin/spinel-core-emit
#   SPINEL_SEAM        the Spinel checkout (default vendor/spinel)
#   CLANG, NM          as for tools/core/spinel-core-build
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$here/../.." && pwd)
fx="$here/fixtures/loops"
DRV="$root/tools/core/spinel-core-build"
GATE="$root/tools/core/core-artifact-gate"
READER="${SPINEL_TYPEDUMP:-$root/tools/contract/build/spinel-typedump}"
. "${ROOT:-$root}/tools/test/source-stamp.sh"
source_stamp kernel "${SPINEL_CORE_BUILD:-$root/tools/mlir/native/build}/bin/spinel-core-check"
source_stamp kernel "${SPINEL_CORE_BUILD:-$root/tools/mlir/native/build}/bin/spinel-core-emit"
source_stamp reader "$READER"
[ -x "$DRV" ] || { echo "loops.sh: no $DRV" >&2; exit 2; }
SPINEL_SEAM="${SPINEL_SEAM:-$root/vendor/spinel}"
export SPINEL_SEAM
if [ -z "${NM:-}" ]; then
  if [ -n "${LLVM_PREFIX:-}" ]; then NM="$LLVM_PREFIX/bin/llvm-nm"; else NM=nm; fi
fi
CC_GATE="${CLANG:-${CC:-cc}}"
SYMPFX=
[ "$(uname -s)" != Darwin ] || SYMPFX=_

w=$(mktemp -d "${TMPDIR:-/tmp}/core-loops.XXXXXX")
trap 'rm -rf "$w"' EXIT INT TERM
pass=0; fail=0
ok()  { pass=$((pass+1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf 'FAIL %s\n' "$1"; [ $# -lt 2 ] || printf '     %s\n' "$2"; }

# build NAME METHOD: fixtures/loops/NAME.rb -> $w/NAME; the driver's stage
# lines go to $w/NAME.build.
build() {
  SPINEL_CORE_VERBOSE=1 "$DRV" --source "$fx/$1.rb" --core "$2" -o "$w/$1" \
    >"$w/$1.build" 2>&1
}

# runs NAME METHOD STATUS STDOUT [STDERR]: STDOUT and STDERR are printf
# formats.
runs() {
  _n=$1; _m=$2; _st=$3
  _want=$(printf "$4"); _werr=$(printf "${5:-}")
  if ! build "$_n" "$_m"; then
    bad "$_n builds" "$(grep -v '^ *\[' "$w/$_n.build" | head -3 | tr '\n' ' ')"
    return
  fi
  set +e; _got=$("$w/$_n" 2>"$w/$_n.err"); _gst=$?; set -e
  _gerr=$(cat "$w/$_n.err")
  if [ "$_got" = "$_want" ] && [ "$_gst" = "$_st" ] && [ "$_gerr" = "$_werr" ]; then
    ok "$_n: $(printf '%s' "$_got" | tr '\n' ' ')(exit $_gst)"
  else
    bad "$_n" "want exit $_st [$(printf '%s' "$_want" | tr '\n' ' ')] [$_werr]; got exit $_gst [$(printf '%s' "$_got" | tr '\n' ' ')] [$_gerr]"
  fi
}

# ---- admitted ---------------------------------------------------------------
# The subtraction gcd: no iteration (9, 9), both branches (21, 15 and 15, 21),
# and several turns of each (48, 18).
runs gcd_sub gcd 0 '9\n3\n3\n6\n'
runs gcd_sub_spelled gcd 0 '6\n7\n'
runs gcd_mod gcd 0 '21\n5\n'
# Each of the eleven `x op= e` operators once, outside a loop; and the six
# that keep a loop-carried local an Integer, inside one.
runs op_assign ops 0 '1600\n'
runs op_assign_loop mix 0 '1000000\n16671\n462\n'
runs sum sum 0 '0\n5050\n'
# `until` tests before the body: no turn for 0. A post-test loop would give 1.
runs until cnt 0 '0\n5\n'
runs modifier f 0 '4\n'
runs unless_in_until f 0 '6\n'
runs step_two f 0 '5\n0\n'
runs param_write f 0 '15\n'
runs nest f 0 '120\n'
runs collatz collatz 0 '111\n'
runs helper_loop f 0 '16\n'
runs loop_calls_loop f 0 '20\n'
runs skipped f 0 '5\n-9223372036854775808\n'
# Checked arithmetic in the body: the first call's value is printed, the
# second ends the program as the uncaught exception would. A wrapping lowering
# would print a negative number and exit 0.
runs add_overflow acc 1 '9223372036854775803\n' 'integer overflow in + (RangeError)'
runs shl_overflow f 1 '4611686018427387904\n' 'integer overflow in << (RangeError)'
runs div_zero f 1 '' 'divided by 0 (ZeroDivisionError)'

# ---- a loop that never ends --------------------------------------------------
# gcd(0, 5) subtracts 0 from 5 for ever. The hosted program marks the call as
# one a signal may interrupt, so SIGINT ends it as Interrupt does. If SIGINT
# does not end it within five seconds, SIGKILL does, and the check fails.
if build never_ends gcd; then
  "$w/never_ends" >/dev/null 2>"$w/never_ends.err" &
  pid=$!
  sleep 1
  kill -INT "$pid" 2>/dev/null || true
  ( sleep 5; kill -KILL "$pid" 2>/dev/null ) &
  dog=$!
  set +e; wait "$pid"; st=$?; set -e
  kill "$dog" 2>/dev/null || true
  [ "$st" = 130 ] && ok "a loop that never ends is ended by SIGINT (exit 130)" \
    || bad "a loop that never ends is ended by SIGINT" "exit $st: $(head -1 "$w/never_ends.err")"
else
  bad "never_ends builds" "$(head -3 "$w/never_ends.build" | tr '\n' ' ')"
fi

# ---- the symbol ---------------------------------------------------------------
# With a loop, the hosted half defines SYMBOL (a wrapper) and the core object
# SYMBOL__pure; the driver says so at stage 2. Without one, the core object
# defines SYMBOL.
if grep -q 'entered through the hosted wrapper; the core object defines spc_[A-Za-z0-9_]*_gcd__pure$' "$w/gcd_sub.build"; then
  ok "with a loop, the core object defines the __pure symbol"
else
  bad "with a loop, the core object defines the __pure symbol" "$(grep '\[2\]' "$w/gcd_sub.build")"
fi
sym=$(sed -n 's/.*\[2\] symbol \(spc_[A-Za-z0-9_]*_gcd\),.*/\1/p' "$w/gcd_sub.build")
if [ -n "$sym" ] && "$NM" "$w/gcd_sub" | grep -q " T ${SYMPFX}${sym}\$" \
   && "$NM" "$w/gcd_sub" | grep -q " T ${SYMPFX}${sym}__pure\$"; then
  ok "the executable has both, the wrapper and the core body"
else
  bad "the executable has both, the wrapper and the core body" "symbol [$sym]"
fi
if SPINEL_CORE_VERBOSE=1 "$DRV" --source "$here/fixtures/lower.rb" --core lower -o "$w/lower" >"$w/lower.build" 2>&1 \
   && grep -q '\[2\] symbol spc_[A-Za-z0-9_]*_lower$' "$w/lower.build" \
   && [ "$("$w/lower")" = 3 ]; then
  ok "without a loop, the core object defines the mapped symbol (prints 3)"
else
  bad "without a loop, the core object defines the mapped symbol" "$(grep '\[2\]' "$w/lower.build")"
fi
# The gate holds the name it is given: an object defining SYMBOL__pure is
# refused when SYMBOL is expected, and the reverse.
printf 'long spc_abc_gcd__pure(long a) { return a; }\n' > "$w/pure.c"
printf 'long spc_abc_gcd(long a) { return a; }\n' > "$w/plain.c"
if "$CC_GATE" -c -O1 "$w/pure.c" -o "$w/pure.o" && "$CC_GATE" -c -O1 "$w/plain.c" -o "$w/plain.o"; then
  "$GATE" "$w/pure.o" spc_abc_gcd__pure >/dev/null 2>&1 \
    && ok "the gate accepts the __pure object under its own name" \
    || bad "the gate accepts the __pure object under its own name"
  if "$GATE" "$w/pure.o" spc_abc_gcd >"$w/g.out" 2>&1; then bad "the gate refuses the __pure object under the plain name" "accepted"
  else ok "the gate refuses the __pure object under the plain name"; fi
  if "$GATE" "$w/plain.o" spc_abc_gcd__pure >"$w/g.out" 2>&1; then bad "the gate refuses the plain object under the __pure name" "accepted"
  else ok "the gate refuses the plain object under the __pure name"; fi
else
  bad "the gate controls compile"
fi

# ---- refused ------------------------------------------------------------------
# refused NAME METHOD REASON: the build fails, names a stage, writes no
# executable, and its output holds REASON (a fixed string).
refused() {
  _n=$1; _m=$2; _r=$3
  if "$DRV" --source "$fx/refused/$_n.rb" --core "$_m" -o "$w/r-$_n" >"$w/r-$_n.out" 2>&1; then
    bad "refuses $_n" "it built"
  elif [ -e "$w/r-$_n" ]; then
    bad "refuses $_n" "it failed and left an executable"
  elif ! grep -q '^spinel-core-build: ' "$w/r-$_n.out"; then
    bad "refuses $_n" "no stage named: $(head -1 "$w/r-$_n.out")"
  elif grep -qF -- "$_r" "$w/r-$_n.out"; then
    ok "refuses $_n ($_r)"
  else
    bad "refuses $_n" "want [$_r]: $(grep -v '^#' "$w/r-$_n.out" | head -2 | tr '\n' ' ')"
  fi
}
# Loop control and the forms around it.
refused break f BreakNode
refused break_value f BreakNode
refused next f NextNode
refused return f ReturnNode
refused post_while f 'loop flags 5'
refused post_until f 'loop flags'
refused loop_last f loop-value
refused loop_assigned f loop-value
refused empty_body f missing-node
# The condition.
refused and_condition f AndNode
refused not_condition f unresolved-call
refused while_true f TrueNode
refused integer_condition f not-lowerable
# The body: forms the route refuses everywhere, inside a loop.
refused multi_assign gcd MultiWriteNode
refused or_assign f LocalVariableOrWriteNode
refused if_no_else mx implicit-nil
refused if_modifier mx implicit-nil
refused body_local_after f nullable-integer
# Accumulators the hosted analysis types as Bignum.
refused factorial fact bigint
refused factorial_op_assign fact bigint
refused fibonacci fib bigint
refused doubling f bigint
refused self_add f bigint
# Loops with a block, and `for`: unchanged.
refused loop_do f unsupported
refused times f unsupported
refused for_in f unsupported

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
