#!/bin/sh
#
# tests/core-boundary/intrinsics-32.sh — the word intrinsics in a 32-bit body,
# run under QEMU's mps2-an521 (a Cortex-M33).
#
#   LLVM_PREFIX=... BAREMETAL_BUILTINS=... [KERNEL=...] [SPINEL_TYPEDUMP=...] [QEMU_ARM=...] \
#     sh tests/core-boundary/intrinsics-32.sh [DIR]
#
# The 32-bit cases of fixtures/intrinsics/cases.tsv, which tests/core-boundary/
# intrinsics.sh cannot run on a 64-bit host: a 32-bit body needs a 32-bit
# target. Each case's entry is built by the kernel for thumbv8m.main with a
# 32-bit body and an i32 boundary. A small program with no RTOS and no C
# library (DIR/main.c, generated here; the reset code and the link script are
# those of tests/freestanding/bare) calls every case once and prints
# `C <id> <status> <value>` on the machine's first UART, then
# `INTRINSICS END`. A failed case must leave the result word untouched, which
# the program checks.
#
# Four parts:
#
#   1. each entry the 32-bit cases name builds;
#   2. the program builds and links;
#   3. it runs under QEMU: the console has the end line, and every case's
#      line is the status and value the table expects. The table must have
#      EXPECT_CASES 32-bit cases, so a table that lost them fails here;
#   4. controls: the comparison of part 3 fails on a console without the end
#      line, on one with a changed value, on one whose failed case touched
#      its result word, and on one that lacks a case's line.
#
# It needs clang and lld (LLVM_PREFIX), the kernel and the reader, Ruby, a
# qemu-system-arm that has the machine mps2-an521 (QEMU_ARM, or on PATH), and
# BAREMETAL_BUILTINS, compiler-rt's builtins archive for ARMv8-M
# (docs/toolchains/compiler-rt-23.1.1): a 32-bit body's 64-bit division is a
# call into it. Without one of them the lane does not start (exit 2).
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
# DIR keeps what the run built; without one a temporary directory is used
# and removed at the end
if [ -n "${1:-}" ]; then DIR=$1; mkdir -p "$DIR"; else DIR=$(mktemp -d "${TMPDIR:-/tmp}/core-intrinsics-32.XXXXXX"); trap 'rm -rf "$DIR"' EXIT; fi
DIR=$(CDPATH= cd -- "$DIR" && pwd)
FIX=$ROOT/tests/core-boundary/fixtures/intrinsics
BARE=$ROOT/tests/freestanding/bare/src
KERNEL=${KERNEL:-$ROOT/tools/mlir/native/build/bin/spinel-core-kernel}
READER=${SPINEL_TYPEDUMP:-$ROOT/tools/contract/build/spinel-typedump}
. "${ROOT:-$root}/tools/test/source-stamp.sh"
source_stamp kernel "$KERNEL"
source_stamp reader "$READER"
LLVM=${LLVM_PREFIX:-/opt/llvm-23.1.1}
CC_BIN=${CLANG:-$LLVM/bin/clang}
RUBY=${RUBY:-ruby}
QEMU=${QEMU_ARM:-qemu-system-arm}
QEMU_TIMEOUT=${QEMU_TIMEOUT:-60}
EXPECT_CASES=27
THUMB="--target=thumbv8m.main-none-eabi -mcpu=cortex-m33+nodsp -mfloat-abi=soft -mthumb -Os -ffreestanding"
pass=0; fail=0; skip=0
ok() { if [ "$2" = "$3" ]; then echo "  pass $1"; pass=$((pass + 1));
       else echo "  FAIL $1 (got '$2', want '$3')"; fail=$((fail + 1)); fi; }
summary() { echo "intrinsics-32: $((pass + fail)) checked, $pass pass, $fail fail, $skip skipped; $(( $(date +%s) - T0 )) s"; [ "$fail" = 0 ]; exit $?; }
T0=$(date +%s)
[ -x "$KERNEL" ] && [ -x "$READER" ] || { echo "intrinsics-32: no kernel or reader" >&2; exit 2; }
[ -x "$CC_BIN" ] || { echo "intrinsics-32: no clang at $CC_BIN" >&2; exit 2; }
[ -f "${BAREMETAL_BUILTINS:-}" ] || { echo "intrinsics-32: BAREMETAL_BUILTINS does not name compiler-rt's builtins archive for ARMv8-M" >&2; exit 2; }
command -v "$QEMU" > /dev/null 2>&1 || { echo "intrinsics-32: no qemu-system-arm ($QEMU); set QEMU_ARM" >&2; exit 2; }
"$QEMU" -machine help 2>/dev/null | grep -q '^mps2-an521 ' || { echo "intrinsics-32: $QEMU has no machine mps2-an521" >&2; exit 2; }
rm -rf "$DIR/obj" "$DIR/controls"; mkdir -p "$DIR/obj" "$DIR/controls"
rm -f "$DIR/main.c" "$DIR/intrinsics.elf" "$DIR/console.txt"

params_of() { "$RUBY" -e 'm = File.read(ARGV[0])[/^def #{ARGV[1]}\(([^)]*)\)/, 1] or abort; puts m.split(/,\s*/)' "$FIX/src/words.rb" "$1"; }
rows=$(grep -v '^#' "$FIX/cases.tsv" | awk -F'\t' '$2 == 32')

echo "intrinsics-32: 1. the 32-bit entries, built for thumbv8m.main"
ok "the table has its 32-bit cases" "$(printf '%s\n' "$rows" | grep -c .)" "$EXPECT_CASES"
for e in $(printf '%s\n' "$rows" | cut -f3 | sort -u); do
  { echo "core-contract 1"; echo "root src/words.rb"; echo "entry $e"; echo "result i32"
    for p in $(params_of "$e"); do echo "param $p scalar i32"; done; } > "$DIR/obj/$e.contract"
  # shellcheck disable=SC2086
  "$KERNEL" "$DIR/obj/$e.contract" --root "$FIX" --typedump "$READER" -o "$DIR/obj/$e.o" --header "$DIR/obj/$e.h" \
    --layout ptr32-i64-32long --int-width=32 --clang "$CC_BIN" -- $THUMB > "$DIR/obj/$e.out" 2>&1
  ok "$e builds" "$?" 0
done

echo "intrinsics-32: 2. the program that calls every case, linked for mps2-an521"
"$RUBY" -e '
  rows = File.readlines(ARGV[0], chomp: true).reject { |l| l.start_with?("#") || l.strip.empty? }.map { |l| l.split("\t") }.select { |r| r[1] == "32" }
  entries = rows.map { |r| r[2] }.uniq
  out = +"/* generated by tests/core-boundary/intrinsics-32.sh: every 32-bit case of\n * fixtures/intrinsics/cases.tsv, called once, its status and value printed\n * on UART0 of the secure Cortex-M33 of QEMU'"'"'s mps2-an521 (a CMSDK APB UART at\n * 0x50200000: DATA 0x0, STATE 0x4 with bit 0 the full transmit buffer, CTRL\n * 0x8 with bit 0 the transmit enable, BAUDDIV 0x10) */\n"
  out << "#include <stdint.h>\n#include \"bm.h\"\n"
  entries.each { |e| out << "#include \"#{e}.h\"\n" }
  out << <<~C

    #define UART0 0x50200000u
    #define UART_DATA (*(volatile uint32_t *)(UART0 + 0x00))
    #define UART_STATE (*(volatile uint32_t *)(UART0 + 0x04))
    #define UART_CTRL (*(volatile uint32_t *)(UART0 + 0x08))
    #define UART_BAUDDIV (*(volatile uint32_t *)(UART0 + 0x10))

    static void putc_(char c)
    {
    \twhile (UART_STATE & 1u) {
    \t}
    \tUART_DATA = (uint32_t)(unsigned char)c;
    }

    void bm_puts(const char *s)
    {
    \twhile (*s)
    \t\tputc_(*s++);
    }

    /* the magnitude as an unsigned value, so INT32_MIN prints too */
    static void put_i32(int32_t v)
    {
    \tchar buf[11];
    \tint n = 0;
    \tuint32_t m = v < 0 ? (uint32_t)0 - (uint32_t)v : (uint32_t)v;
    \tdo {
    \t\tbuf[n++] = (char)(\x27 0\x27 + (int)(m % 10u));
    \t\tm /= 10u;
    \t} while (m);
    \tif (v < 0)
    \t\tputc_(\x27-\x27);
    \twhile (n)
    \t\tputc_(buf[--n]);
    }

    static void line(const char *id, int32_t st, int32_t r, int32_t sentinel)
    {
    \tbm_puts("C ");
    \tbm_puts(id);
    \tputc_(\x27 \x27);
    \tput_i32(st);
    \tputc_(\x27 \x27);
    \tif (st != 0)
    \t\tbm_puts(r == sentinel ? "untouched" : "TOUCHED");
    \telse
    \t\tput_i32(r);
    \tputc_(\x27\\n\x27);
    }

    static const int32_t sentinel = -123456789;

    void bm_main(void)
    {
    \tint32_t r, st;

    \tUART_BAUDDIV = 16;
    \tUART_CTRL = 1;
    \tbm_puts("INTRINSICS BEGIN\\n");
  C
  out.gsub!("\x27 0\x27", "\x270\x27")
  rows.each do |id, _w, e, args, _s, _v|
    a = args.split(",").map { |x| "(int32_t)(#{Integer(x)}u)" }.join(", ")
    out << "\tr = sentinel;\n\tst = spinel_core_#{e}(#{a}, &r);\n\tline(\"#{id}\", st, r, sentinel);\n"
  end
  out << "\tbm_puts(\"INTRINSICS END\\n\");\n}\n"
  File.write(ARGV[1], out)' "$FIX/cases.tsv" "$DIR/main.c"
# shellcheck disable=SC2086
"$CC_BIN" $THUMB -fno-builtin -nostdlib -static -Wall -Wextra -Werror -I "$DIR/obj" -I "$BARE" \
  -fuse-ld=lld -Wl,-T,"$BARE/link.ld" -Wl,-Map,"$DIR/intrinsics.map" -o "$DIR/intrinsics.elf" \
  "$BARE/start.c" "$DIR/main.c" "$DIR"/obj/*.o "$BAREMETAL_BUILTINS" > "$DIR/link.out" 2>&1
ok "the program links" "$?|$([ -s "$DIR/intrinsics.elf" ] && echo elf)" "0|elf"
[ -s "$DIR/intrinsics.elf" ] || { sed 's/^/      /' "$DIR/link.out" | head -8; summary; }

echo "intrinsics-32: 3. under QEMU"
: > "$DIR/console.raw"
"$QEMU" -machine mps2-an521 -cpu cortex-m33 -m 16 -display none -monitor none \
  -serial file:"$DIR/console.raw" -kernel "$DIR/intrinsics.elf" 2> "$DIR/qemu.err" &
qpid=$!
i=0
while [ "$i" -lt "$QEMU_TIMEOUT" ]; do
  grep -q -e '^INTRINSICS END' -e 'FATAL' "$DIR/console.raw" 2>/dev/null && break
  kill -0 "$qpid" 2>/dev/null || break
  sleep 1; i=$((i + 1))
done
kill "$qpid" 2>/dev/null; wait "$qpid" 2>/dev/null
tr -d '\r' < "$DIR/console.raw" > "$DIR/console.txt"

# judge CONSOLE: one line per check of a console against the table: the end
# line, then every 32-bit case. A console that stops early has no end line and
# fails there, whatever cases it printed.
judge() {
  if [ "$(grep -c '^INTRINSICS END$' "$1")" = 1 ]; then echo "  pass the console has the program's end line"
  else echo "  FAIL the console has the program's end line (the last line is '$(tail -1 "$1")')"; fi
  printf '%s\n' "$rows" | while IFS="$(printf '\t')" read -r id width entry args status value; do
    got=$(sed -n "s/^C $id //p" "$1")
    case $status in ok) want="0 $value" ;; arithmetic) want="2 untouched" ;; *) want="a status the table has (it says '$status')" ;; esac
    if [ "$got" = "$want" ]; then echo "  pass $id: $entry($args) at 32 bits"
    else echo "  FAIL $id: $entry($args) at 32 bits (got '$got', want '$want')"; fi
  done
}
judge "$DIR/console.txt" > "$DIR/cases.out"
cat "$DIR/cases.out"
pass=$((pass + $(grep -c '^  pass' "$DIR/cases.out"))); fail=$((fail + $(grep -c '^  FAIL' "$DIR/cases.out")))

echo "intrinsics-32: 4. controls: the comparison can fail"
# each control is the run's console with one thing changed; judge must fail
# on exactly the lines named
control() { # NAME FILE WANT-FAILS PATTERN-OF-THE-FAILING-LINE
  judge "$2" > "$2.out"
  ok "$1" "$(grep -c '^  FAIL' "$2.out")|$(grep '^  FAIL' "$2.out" | grep -c -e "$4")" "$3|$3"
}
okid=$(printf '%s\n' "$rows" | awk -F'\t' '$5 == "ok" { print $1; exit }')
arid=$(printf '%s\n' "$rows" | awk -F'\t' '$5 == "arithmetic" { print $1; exit }')
C=$DIR/controls
grep -v '^INTRINSICS END$' "$DIR/console.txt" > "$C/no-end.txt"
control "a console that stops before the end line fails" "$C/no-end.txt" 1 "end line"
sed "s/^C $okid 0 .*/C $okid 0 12345/" "$DIR/console.txt" > "$C/value.txt"
control "a changed value fails its case" "$C/value.txt" 1 "FAIL $okid:"
sed "s/^C $arid 2 untouched/C $arid 2 TOUCHED/" "$DIR/console.txt" > "$C/touched.txt"
control "a failed case that touched its result word fails" "$C/touched.txt" 1 "FAIL $arid:"
grep -v "^C $okid " "$DIR/console.txt" > "$C/missing.txt"
control "a case with no line fails" "$C/missing.txt" 1 "FAIL $okid:"
summary
