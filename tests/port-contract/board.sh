#!/bin/sh
#
# tests/port-contract/board.sh -- the board file's validator, on a control
# board and a control chip family. It needs Ruby only.
#
#   sh tests/port-contract/board.sh
#
# fixtures/boards/ has one board file and the statement of its chip family,
# with names that are not those of any real board: tools/platform/board-check
# takes every key from the schema and the family's statement.
#
# What it establishes:
#
#   1. The control board is valid, --values prints its values, the
#      policy's and the family's, and --head its family's directory. Of
#      several chip directories, the first that holds the family is used.
#   2. Each damaged board file is refused, for its reason and no other: a key
#      the family does not list, a listed key left out, a value with a unit
#      suffix or not in plain decimal, a value out of its range or not among the allowed ones, a
#      policy key the schema does not have, another schema version, a chip
#      family that has no statement in any directory given (the refusal
#      names each place).
#   3. A chip statement without the two build keys (objects, image) is
#      valid, and one with a damaged build key is refused.
#      A damaged chip statement is refused or cannot be read: an unknown key,
#      an architecture the port contract does not have, a rule of no type, a
#      board key that is the schema's own.
#   4. What cannot be read is exit 2 with its own message: a key given
#      twice, a missing file, a bad command line.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
FIX="$ROOT/tests/port-contract/fixtures/boards"
CHECK="$ROOT/tools/platform/board-check"
SCHEMA="$ROOT/tools/platform/board-schema.yaml"
CONTRACT="$ROOT/tools/platform/port-contract.yaml"
RUBY="${RUBY:-ruby}"
command -v "$RUBY" >/dev/null 2>&1 || { echo "port-contract board: no ruby at '$RUBY'" >&2; exit 2; }

W=$(mktemp -d "${TMPDIR:-/tmp}/port-board.XXXXXX")
W=$(CDPATH= cd -- "$W" && pwd) # as one path: a TMPDIR that ends in a slash gives two slashes
trap 'rm -rf "$W"' EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*" >&2; }

# run BOARD [CHIP-DIR]: exit status in $rc, output in $W/out
run() {
  rc=0
  "$RUBY" "$CHECK" --schema "$SCHEMA" --chip-dir "${2:-$FIX/chip}" --contract "$CONTRACT" "$1" >"$W/out" 2>&1 || rc=$?
}
# expect LABEL STATUS COUNT TEXT: the last run ended STATUS, said TEXT, and
# (when refused) gave exactly COUNT reasons
expect() {
  if [ "$rc" -eq "$2" ] && grep -qF -- "$4" "$W/out" &&
     { [ "$2" -ne 1 ] || grep -qxF "board-check: refused ($3)" "$W/out"; }; then ok
  else bad "$1: expected exit $2 with '$4', got $rc"; cat "$W/out" >&2
  fi
}
# board LABEL SED COUNT TEXT: the control board with SED applied is refused
board() {
  sed "$2" "$FIX/board/tboard.yaml" >"$W/tboard.yaml"
  if cmp -s "$FIX/board/tboard.yaml" "$W/tboard.yaml"; then bad "$1: the mutation changed nothing"; return 0; fi
  run "$W/tboard.yaml"
  expect "$1" "${5:-1}" "$3" "$4"
}
# chip LABEL SED STATUS COUNT TEXT: the same with the family's statement
chip() {
  rm -rf "$W/chip"; mkdir -p "$W/chip/tchip"
  sed "$2" "$FIX/chip/tchip/chip.yaml" >"$W/chip/tchip/chip.yaml"
  if cmp -s "$FIX/chip/tchip/chip.yaml" "$W/chip/tchip/chip.yaml"; then bad "$1: the mutation changed nothing"; return 0; fi
  run "$FIX/board/tboard.yaml" "$W/chip"
  expect "$1" "$3" "$4" "$5"
}

# ---- 1. the control board
run "$FIX/board/tboard.yaml"
expect "control board" 0 0 "board-check: valid (tboard, chip tchip)"
"$RUBY" "$CHECK" --schema "$SCHEMA" --chip-dir "$FIX/chip" --values "$FIX/board/tboard.yaml" >"$W/values"
cat >"$W/values.want" <<'WANT'
board.clock.crystal_hz	12000000
board.console.uart	0
board.console.baud	115200
board.flash.boot	plain
policy.stack_bytes	32768
policy.gc_threshold_kb	16
policy.gc_slab	0
chip.flash.origin	268435456
chip.flash.size_bytes	1048576
chip.flash.head_bytes	16
chip.ram.origin	536870912
chip.ram.size_bytes	65536
WANT
if cmp -s "$W/values" "$W/values.want"; then ok; else bad "--values"; diff "$W/values.want" "$W/values" >&2 || true; fi
board "optional key left out" '/^flash:/d' 0 "board-check: valid" 0
"$RUBY" "$CHECK" --schema "$SCHEMA" --chip-dir "$FIX/chip" --head "$FIX/board/tboard.yaml" >"$W/head"
if [ "$(cat "$W/head")" = "$(printf 'tboard\ttchip\tm0plus\tarmv6-m\t%s' "$FIX/chip/tchip")" ]; then ok; else bad "--head: $(cat "$W/head")"; fi
# several chip directories: the first that holds the family is used
mkdir -p "$W/first/tchip" "$W/empty"
sed 's/^cpu: m0plus/cpu: m33/' "$FIX/chip/tchip/chip.yaml" >"$W/first/tchip/chip.yaml"
two() { "$RUBY" "$CHECK" --schema "$SCHEMA" --chip-dir "$1" --chip-dir "$2" --head "$FIX/board/tboard.yaml" | cut -f3,5; }
if [ "$(two "$W/first" "$FIX/chip")" = "$(printf 'm33\t%s' "$W/first/tchip")" ] &&
   [ "$(two "$FIX/chip" "$W/first")" = "$(printf 'm0plus\t%s' "$FIX/chip/tchip")" ] &&
   [ "$(two "$W/empty" "$FIX/chip")" = "$(printf 'm0plus\t%s' "$FIX/chip/tchip")" ]; then ok
else bad "two chip directories: the first that holds the family"
fi

# ---- 2. damaged board files
board "key the family does not list" 's/uart: 0,/uart: 0, tx: 4,/' 1 "has console.tx, which no rule lists"
board "address in place of an instance" 's/uart: 0,/uart: 1073971200,/' 1 "console.uart is 1073971200, not one of 0, 1"
board "listed key left out" 's/, baud: 115200//' 1 "lacks console.baud"
board "unit suffix" 's/crystal_hz: 12000000/crystal_hz: 12M/' 1 'clock.crystal_hz must be a plain integer, got "12M"'
board "hexadecimal" 's/crystal_hz: 12000000/crystal_hz: 0xB71B00/' 1 "0xB71B00 is not a plain decimal integer"
board "a leading zero, read as octal" 's/baud: 115200/baud: 0605/' 1 "0605 is not a plain decimal integer"
board "digit separators" 's/crystal_hz: 12000000/crystal_hz: 12_000_000/' 1 "12_000_000 is not a plain decimal integer"
board "not an integer" 's/crystal_hz: 12000000/crystal_hz: 12.0e6/' 1 "clock.crystal_hz must be a plain integer"
board "out of range" 's/crystal_hz: 12000000/crystal_hz: 48000000/' 1 "clock.crystal_hz is 48000000, above 15000000"
board "name not allowed" 's/boot: plain/boot: octal/' 1 'flash.boot is "octal", not one of plain, quad'
board "policy key the schema lacks" 's/gc_slab: 0/gc_slab: 0\
  heap_bytes: 4096/' 1 "policy has heap_bytes, which no rule lists"
board "policy value not allowed" 's/gc_slab: 0/gc_slab: 2/' 1 "policy: gc_slab is 2, not one of 0, 1"
board "policy key left out" '/stack_bytes/d' 1 "policy lacks stack_bytes"
board "another version" 's/^version: 1/version: 2/' 1 "version must be 1, got 2"
board "another format" 's/^format: spinel-board/format: board/' 1 "format must be spinel-board"
board "chip without a statement" 's/^chip: tchip/chip: nochip/' 1 "chip nochip has no statement"
board "chip that is a path" 's|^chip: tchip|chip: ../tchip|' 1 "chip must name a chip family"

sed "s/^chip: tchip/chip: nochip/" "$FIX/board/tboard.yaml" >"$W/tboard.yaml"
rc=0; "$RUBY" "$CHECK" --schema "$SCHEMA" --chip-dir "$W/empty" --chip-dir "$FIX/chip" "$W/tboard.yaml" >"$W/out" 2>&1 || rc=$?
expect "chip in none of two directories" 1 1 "chip nochip has no statement at $W/empty/nochip/chip.yaml, $FIX/chip/nochip/chip.yaml"

# ---- 3. damaged chip statements
chip "the build keys left out" '/^objects:/d; /^image:/,/^  uf2:/d' 0 0 "board-check: valid"
chip "unknown key" 's/^cpu: m0plus/cpu: m0plus\
vendor: acme/' 1 1 "unknown key vendor"
chip "architecture the contract lacks" 's/archs: \[armv6-m\]/archs: [armv9-z]/' 1 1 "architecture armv9-z is not one of the contract's"
chip "rule of no type" 's/{ type: int, min: 300 }/{ min: 300 }/' 2 0 "type must be int or name"
chip "name rule without its list" 's/{ type: name, one_of: \[plain, quad\], optional: true }/{ type: name }/' 2 0 "a name needs one_of"
chip "board key that is the schema's" 's/^  console.baud:/  policy.stack_bytes:/' 2 0 "board key policy.stack_bytes is the schema's own"
chip "family value that is no value" 's/size_bytes: 65536/size_bytes: 64K/' 1 1 "values.ram.size_bytes must be a plain integer or a name"
chip "objects outside the family's directory" 's|^objects: boot/object.rb|objects: ../other/object.rb|' 1 1 "objects must be a path inside the family's directory"
chip "objects that is no path" 's|^objects: boot/object.rb|objects: 7|' 1 1 "objects must be a path inside the family's directory"
chip "image key nobody reads" 's/^  uf2: .*/&\
  hex: true/' 1 1 "image: unknown key hex"
chip "flash origin without its size" '/^  flash_bytes:/d' 1 1 "image gives flash_origin without flash_bytes"
chip "flash size that names no value" 's/flash_bytes: chip.flash.size_bytes/flash_bytes: chip.flash.kilobytes/' 1 1 "image.flash_bytes must be a number or name an integer value of the board"
chip "flash origin that names a name" 's/flash_origin: chip.flash.origin/flash_origin: board.flash.boot/' 1 1 "image.flash_origin must be a number or name an integer value of the board"
chip "UF2 family id of no type" 's/family_id: 0x12345678/family_id: some-chip/' 1 1 "image.uf2 must be {family_id: N}"
chip "UF2 with a key of its own" 's/family_id: 0x12345678/family_id: 0x12345678, pages: 3/' 1 1 "image.uf2 must be {family_id: N}"
chip "head of another version" 's/^version: 1/version: 3/' 1 1 "version must be 1, got 3"

# ---- 4. what cannot be read
board "key given twice" 's/^console: .*/&\
console: { uart: 1, baud: 9600 }/' 0 "key console is given twice" 2
run "$W/absent.yaml"; expect "missing board file" 2 0 "no such file"
rc=0; "$RUBY" "$CHECK" --schema "$SCHEMA" "$FIX/board/tboard.yaml" >"$W/out" 2>&1 || rc=$?
expect "no chip directory" 2 0 "usage:"
rc=0; "$RUBY" "$CHECK" --schema "$CONTRACT" --chip-dir "$FIX/chip" "$FIX/board/tboard.yaml" >"$W/out" 2>&1 || rc=$?
expect "a schema that is not one" 2 0 "unknown key"

echo "port-contract board: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
