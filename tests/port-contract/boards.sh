#!/bin/sh
#
# tests/port-contract/boards.sh -- real full-tier builds of every board
# spinel-bare-full finds a board file for, held to the board schema and to the
# shipped port contract. spinel-bare-full is tools/bare-full's driver, the
# bare-metal build the contract holds.
#
#   sh tests/port-contract/boards.sh DIR
#
# DIR is an empty scratch directory outside the checkout. The boards are the
# lines of `spinel-bare-full boards`: the board files of the port directories
# the driver searches, which are those of BAREMETAL_PORT_PATH, then the
# control board's (fixtures/boards, which the lane adds), then the driver's
# own. The lane has no list and no search of its own, and takes each board's
# chip family, core and architecture from the files. So a board and a chip
# family outside this repository are held as the ones in it are: name their
# port directory in BAREMETAL_PORT_PATH. The control board, tboard, is built
# and checked like the others and never run; it is what builds the ARMv6-M
# core, a family's own object, a link part that inserts a section, and a UF2
# image on every run. For each board, in order:
#
#   1. tools/platform/board-check: the board file is valid for its family,
#      and the validator, given the same directories, takes the family from
#      the directory the driver takes it from.
#   2. The build of fixtures/hello.rb (the runtime for the board's core
#      first, unless one is given).
#   3. The header the build generated from the two files (bf-board.h in the
#      build's directory) has one define for each integer value board-check
#      reads, with that value, and no other: the build and the validator read
#      the files alike. The comparison is shown to fail on a changed value
#      and on a dropped one.
#   4. tools/platform/port-check: the build's parts, image and link map hold
#      to the contract. The report is left in DIR as
#      <board>.port-report.json.
#   5. Three controls show the lane can refuse this build:
#        checked as an architecture its chip family does not list, it is
#        refused over the atomics;
#        against a copy of the contract without one of the chip's console
#        names, the chip's object is refused as exporting a stray global and
#        the base as using an undeclared one;
#        against a copy without the constructor bounds' row, the C library's
#        use of them is refused.
#   6. The build's parts can be changed, and each change is where it should
#      be and nowhere else. Each is some steps run again (--steps) on a copy
#      of the build's directory, the link and image steps unless said:
#        an unknown step is a usage error, and a step whose input is missing
#        names the step that makes it;
#        the runtime's link part replaced by a copy of itself gives the same
#        ELF file;
#        a part of the user's (fixtures/user-part.ld, a 16-byte section after
#        .rodata) makes the flash image 16 bytes longer, with that section
#        in the ELF file;
#        the stack size set to half of the board's (the values step too)
#        gives that __stack_size and an image of the same length;
#        the image formats are those the chip family declares (a UF2 file
#        exactly when it has image.uf2);
#        where the family says what its flash is, a runtime part that stores
#        .data in RAM is refused with the address, and no image file is left.
#   7. With PORT_BARE_FULL_BEFORE, the same program built by that driver
#      gives the same flash image, byte for byte (see below). A board that
#      driver does not have is not compared.
#
# Then, once, on the first board that was built:
#
#   8. Port directories. A copy of the board's family in a directory given
#      with --port-dir is used in place of the first one, the driver says so,
#      the build's record (found) names the copy, and the ELF file is the
#      same; a later step run without that directory is refused. A board file
#      naming a family no directory holds is refused with the directories
#      searched. A copy of the family with one more global builds, and
#      port-check refuses it as a stray export. A directory with neither
#      board/ nor chip/ is a usage error.
#
# No image is run: what a board does is not this lane's subject.
#
# It needs what a bare-full build needs. CORE below is a chip family's `cpu`
# in upper case (M33, M0PLUS):
#
#   LLVM_PREFIX            the LLVM 23.1.1 release
#   vendor/spinel          built (or SPINEL_DIR naming a built Spinel at the
#                          same pin), as tools/bare-full/README.md says
#   PORT_<CORE>_PICOLIBC   picolibc's install prefix for that core
#   PORT_<CORE>_BUILTINS   compiler-rt's builtins archive for that core
#   PORT_<CORE>_RUNTIME    optional: a libspinel_rt_bare.a already built with
#                          `spinel-bare-full runtime --cpu ...`, to save the time
#   BAREMETAL_PORT_PATH    optional: port directories with boards and chip
#                          families to hold besides the driver's own
#   PORT_BARE_FULL_BEFORE  optional: another spinel-bare-full driver, of the
#                          revision an edit started from. A change that only
#                          moves code and values must leave every flash image
#                          as it was; with this set, a board whose image
#                          differs fails the lane. The older driver need not
#                          have board files: it is given the board's name.
#   PORT_BARE_FULL         optional: a spinel-bare-full driver to hold instead
#                          of this checkout's (it is read and run, never
#                          edited). It must have the `boards` subcommand.
#
# Without them the lane prints NOT RUN and the reason, and exits 0;
# REQUIRE_ALL=1 makes that a failure. A core whose variables are missing is
# not run while the others are, and the image comparison is NOT RUN without
# PORT_BARE_FULL_BEFORE.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HERE="$ROOT/tests/port-contract"
CHECK="$ROOT/tools/platform/port-check"
BOARD_CHECK="$ROOT/tools/platform/board-check"
SCHEMA="$ROOT/tools/platform/board-schema.yaml"
CONTRACT="$ROOT/tools/platform/port-contract.yaml"
RUBY="${RUBY:-ruby}"

die() { echo "port-contract boards: $*" >&2; exit 2; }
[ $# -eq 1 ] || die "usage: boards.sh DIR"
mkdir -p "$1"
OUT=$(CDPATH= cd -- "$1" && pwd)
case "$OUT/" in "$ROOT"/*) die "DIR must be outside the checkout" ;; esac

pass=0
fail=0
notrun=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*" >&2; }
skip() { notrun=$((notrun + 1)); echo "NOT RUN ($1)"; }
finish() {
  echo "port-contract boards: $pass passed, $fail failed, $notrun not run"
  [ "$fail" -eq 0 ] || exit 1
  if [ "$notrun" -gt 0 ] && [ "${REQUIRE_ALL:-}" = 1 ]; then exit 1; fi
  exit 0
}

BF="${PORT_BARE_FULL:-$ROOT/tools/bare-full/spinel-bare-full}"
[ -x "$BF" ] || die "not a spinel-bare-full driver: $BF"
if [ -z "${LLVM_PREFIX:-}" ]; then
  skip "no cross toolchain: set LLVM_PREFIX"
  finish
fi
if [ -z "${SPINEL_DIR:-}" ] && [ -z "${PORT_BARE_FULL:-}" ] && [ ! -x "$ROOT/vendor/spinel/bin/spinel" ]; then
  skip "vendor/spinel is not built, and SPINEL_DIR is not set"
  finish
fi
BFDIR=$(CDPATH= cd -- "$(dirname -- "$BF")" && pwd)
# the control board and its family (fixtures/boards, a port directory) are
# built with the others: they are searched after the caller's directories
BAREMETAL_PORT_PATH="${BAREMETAL_PORT_PATH:+$BAREMETAL_PORT_PATH:}$HERE/fixtures/boards"
export BAREMETAL_PORT_PATH
# the boards, and where each one's file and chip family are, as the driver finds them
"$BF" boards >"$OUT/boards.tsv" 2>"$OUT/boards.log" || { cat "$OUT/boards.log" >&2; die "$BF boards failed"; }
if [ ! -s "$OUT/boards.tsv" ]; then
  skip "no board files in the port directories"
  finish
fi
# the validator is given the same directories in the same order
CHIPDIRS=$(
  old=$IFS; IFS=:
  for d in ${BAREMETAL_PORT_PATH:-}; do [ -d "$d/chip" ] && printf '%s\n' "$d/chip"; done
  IFS=$old
  printf '%s\n' "$BFDIR/chip")
board_check() {
  (
    set --
    while IFS= read -r d; do set -- "$@" --chip-dir "$d"; done <<DIRS
$CHIPDIRS
DIRS
    exec "$RUBY" "$BOARD_CHECK" --schema "$SCHEMA" "$@" "$BC_MODE" ${BC_CONTRACT:+--contract "$CONTRACT"} "$BC_FILE"
  )
}
BEFORE="${PORT_BARE_FULL_BEFORE:-}"
[ -z "$BEFORE" ] || [ -x "$BEFORE" ] || die "PORT_BARE_FULL_BEFORE is not a program: $BEFORE"
ARCHS=$("$RUBY" -ryaml -e 'puts YAML.safe_load(File.read(ARGV[0]))["archs"]' "$CONTRACT")

var() { eval "printf '%s' \"\${$1:-}\""; }

# expect LABEL TEXT...: the last check was exit 1 with every TEXT among its refusals
expect() {
  label=$1; shift
  good=1
  [ "$rc" -eq 1 ] || good=0
  for text in "$@"; do grep -qF -- "$text" "$OUT/control-$board.log" || good=0; done
  if [ "$good" -eq 1 ]; then ok
  else bad "$board: $label: expected a refusal with $*, got exit $rc"; cat "$OUT/control-$board.log" >&2
  fi
}

# header_agrees VALUES HEADER: HEADER has one define for each integer value
# of VALUES (board-check --values), named from the key path, and no other
header_agrees() {
  "$RUBY" -e '
    want = File.readlines(ARGV[0], chomp: true).filter_map do |l|
      key, value = l.split("\t", 2)
      [("bf." + key).upcase.tr(".", "_"), Integer(value)] if value =~ /\A-?\d+\z/
    end.to_h
    have = File.readlines(ARGV[1], chomp: true).filter_map do |l|
      m = l.match(/\A#define\s+(\w+)\s+(\S+)\s*\z/) and [m[1], Integer(m[2])]
    end.to_h
    errs = (want.keys - have.keys).map { |k| "the header lacks #{k}" } +
           (have.keys - want.keys).map { |k| "the header has #{k}, which no value gives" } +
           (want.keys & have.keys).reject { |k| want[k] == have[k] }.map { |k| "#{k} is #{have[k]}, the file says #{want[k]}" }
    abort errs.join("\n") unless errs.empty? && !want.empty?
  ' "$1" "$2"
}

lane() {
  board=$1; file=$2; chipdir=$4

  # 1. the board file, and the validator finding the family where the driver does
  if ! head=$(BC_MODE=--head BC_CONTRACT=1 BC_FILE=$file board_check 2>"$OUT/board-$board.log"); then
    bad "$board: the board file is not valid"; cat "$OUT/board-$board.log" >&2
    return 0
  fi
  ok
  if [ "$(printf '%s' "$head" | cut -f5)" = "$chipdir" ]; then ok
  else bad "$board: the driver takes the family from $chipdir, the validator from $(printf '%s' "$head" | cut -f5)"
  fi
  cpu=$(printf '%s' "$head" | cut -f3)
  arch=$(printf '%s' "$head" | cut -f4 | cut -d, -f1)
  listed=$(printf '%s' "$head" | cut -f4)
  core=$(printf '%s' "$cpu" | tr '[:lower:]' '[:upper:]')
  libc=$(var "PORT_${core}_PICOLIBC")
  builtins=$(var "PORT_${core}_BUILTINS")
  runtime=$(var "PORT_${core}_RUNTIME")
  if [ -z "$libc" ] || [ -z "$builtins" ]; then
    skip "$board: no PORT_${core}_PICOLIBC or PORT_${core}_BUILTINS"
    return 0
  fi

  # 2. the build
  if [ -z "$runtime" ]; then
    runtime="$OUT/rt-$cpu/libspinel_rt_bare.a"
    if [ ! -f "$runtime" ]; then
      BAREMETAL_PICOLIBC="$libc" BAREMETAL_BUILTINS="$builtins" "$BF" runtime --cpu "$cpu" "$OUT/rt-$cpu" \
        >"$OUT/rt-$cpu.log" 2>&1 || { bad "$board: the runtime for $cpu did not build (see $OUT/rt-$cpu.log)"; return 0; }
    fi
  fi
  elf="$OUT/hello-$board.elf"
  rm -rf "$elf" "$elf.d"
  BAREMETAL_PICOLIBC="$libc" BAREMETAL_BUILTINS="$builtins" "$BF" build --runtime "$runtime" --board "$board" \
    "$HERE/fixtures/hello.rb" "$elf" >"$OUT/build-$board.log" 2>&1 ||
    { bad "$board: the build failed (see $OUT/build-$board.log)"; return 0; }

  # 3. the generated header against the validator's reading
  BC_MODE=--values BC_CONTRACT= BC_FILE=$file board_check >"$OUT/values-$board.tsv"
  if header_agrees "$OUT/values-$board.tsv" "$elf.d/bf-board.h" 2>"$OUT/header-$board.log"; then ok
  else bad "$board: the generated header and the board file disagree"; cat "$OUT/header-$board.log" >&2
  fi
  # ... and the comparison can fail: one value changed, one value dropped
  awk -F '\t' 'BEGIN { OFS = FS } !done && $2 ~ /^[0-9]+$/ { $2 = $2 + 1; done = 1 } { print }' \
    "$OUT/values-$board.tsv" >"$OUT/values-$board.changed"
  sed '1d' "$OUT/values-$board.tsv" >"$OUT/values-$board.dropped"
  if header_agrees "$OUT/values-$board.changed" "$elf.d/bf-board.h" 2>/dev/null ||
     header_agrees "$OUT/values-$board.dropped" "$elf.d/bf-board.h" 2>/dev/null; then
    bad "$board: the header comparison passes a changed or a dropped value"
  else ok
  fi

  # 4. the contract. An object named plat-* is the base's and one named
  # chip-* the chip's; port-check refuses a file the image links that was
  # given to no part, so an object of another name is not passed over.
  set -- --tier full --part program="$elf.d/app.o" --part runtime="$runtime" \
    --part builtins="$builtins" --part libc="$libc/lib/libc.a" --image "$elf" --map "$elf.map"
  for o in "$elf.d"/plat-*.o; do [ -f "$o" ] && set -- "$@" --part base="$o"; done
  for o in "$elf.d"/chip-*.o; do [ -f "$o" ] && set -- "$@" --part chip="$o"; done
  report="$OUT/$board.port-report.json"
  rm -f "$report"
  if "$RUBY" "$CHECK" --contract "$CONTRACT" "$@" --arch "$arch" --report "$report" >"$OUT/check-$board.log" 2>&1 &&
     [ -s "$report" ]; then ok
  else bad "$board: not accepted"; cat "$OUT/check-$board.log" >&2
  fi

  # 5. controls
  other=
  for a in $ARCHS; do
    case ",$listed," in *",$a,"*) ;; *) other=$a ;; esac
  done
  if [ -n "$other" ]; then
    rc=0
    "$RUBY" "$CHECK" --contract "$CONTRACT" "$@" --arch "$other" >"$OUT/control-$board.log" 2>&1 || rc=$?
    expect "as $other" "__atomic_"
  else skip "$board: the family lists every architecture of the contract"
  fi

  sed 's/names: \[bf_console_init, bf_putc\]/names: [bf_console_init]/' "$CONTRACT" >"$OUT/no-putc.yaml"
  cmp -s "$CONTRACT" "$OUT/no-putc.yaml" && { bad "$board: the console control changed nothing"; return 0; }
  rc=0
  "$RUBY" "$CHECK" --contract "$OUT/no-putc.yaml" "$@" --arch "$arch" >"$OUT/control-$board.log" 2>&1 || rc=$?
  expect "a console name removed" "stray: chip exports bf_putc" "undeclared: base uses bf_putc from chip"

  sed 's/names: \[__bothinit_array_start, __bothinit_array_end, /names: [/' "$CONTRACT" >"$OUT/no-ctors.yaml"
  cmp -s "$CONTRACT" "$OUT/no-ctors.yaml" && { bad "$board: the constructor control changed nothing"; return 0; }
  rc=0
  "$RUBY" "$CHECK" --contract "$OUT/no-ctors.yaml" "$@" --arch "$arch" >"$OUT/control-$board.log" 2>&1 || rc=$?
  expect "the constructor bounds removed" "undeclared: libc uses __bothinit_array_start from link"

  # 6. the parts of the build, changed
  build_env() { BAREMETAL_PICOLIBC="$libc" BAREMETAL_BUILTINS="$builtins" "$@"; }
  # again NAME STEPS ARGS...: those steps on a copy of the build's directory,
  # as $OUT/NAME-<board>.elf; the status is left in $rc
  again() {
    name=$1; steps=$2; shift 2
    alt="$OUT/$name-$board.elf"
    rm -rf "$alt" "$alt".*
    cp -R "$elf.d" "$alt.d"
    rc=0
    build_env "$BF" build --runtime "$runtime" --board "$board" --steps "$steps" "$@" \
      "$HERE/fixtures/hello.rb" "$alt" >"$OUT/$name-$board.log" 2>&1 || rc=$?
  }
  size_of() { wc -c <"$1" | tr -d ' '; }

  rc=0
  build_env "$BF" build --runtime "$runtime" --board "$board" --steps link,flash \
    "$HERE/fixtures/hello.rb" "$OUT/steps-$board.elf" >"$OUT/steps-$board.log" 2>&1 || rc=$?
  if [ "$rc" -eq 64 ]; then ok; else bad "$board: an unknown step: expected exit 64, got $rc"; fi
  rm -rf "$OUT/steps-$board.elf.d"
  rc=0
  build_env "$BF" build --runtime "$runtime" --board "$board" --steps link \
    "$HERE/fixtures/hello.rb" "$OUT/steps-$board.elf" >"$OUT/steps-$board.log" 2>&1 || rc=$?
  if [ "$rc" -eq 2 ] && grep -q "run step values first" "$OUT/steps-$board.log"; then ok
  else bad "$board: a step without its input: expected exit 2 naming the step, got $rc"; cat "$OUT/steps-$board.log" >&2
  fi

  cp "$BFDIR/platform/common/link.ld" "$OUT/runtime-copy.ld"
  again same link,image --link-runtime "$OUT/runtime-copy.ld"
  if [ "$rc" -eq 0 ] && cmp -s "$elf" "$alt"; then ok
  else bad "$board: the runtime's part replaced by a copy: not the same ELF file (exit $rc)"
  fi

  again user link,image --link-add "$HERE/fixtures/user-part.ld"
  if [ "$rc" -eq 0 ] && [ "$(size_of "$alt.bin")" -eq $(($(size_of "$elf.bin") + 16)) ] &&
     "$LLVM_PREFIX/bin/llvm-readelf" -S -W "$alt" | grep -q ' \.user_table  *PROGBITS .* 000010 '; then ok
  else bad "$board: a part of the user's: expected a 16-byte .user_table and an image 16 bytes longer (exit $rc)"
  fi

  stack=$(awk -F '\t' '$1 == "policy.stack_bytes" { print $2 / 2 }' "$OUT/values-$board.tsv")
  again stack values,link,image --set "policy.stack_bytes=$stack"
  if [ "$rc" -eq 0 ] && [ "$(size_of "$alt.bin")" -eq "$(size_of "$elf.bin")" ] && ! cmp -s "$elf.bin" "$alt.bin" &&
     [ "$("$LLVM_PREFIX/bin/llvm-nm" "$alt" | awk '$3 == "__stack_size" { print $1 }')" = "$(printf '%08x' "$stack")" ]; then ok
  else bad "$board: the stack size set to $stack: expected that __stack_size and an image of the same length (exit $rc)"
  fi

  declared=$("$RUBY" -ryaml -e 'i = YAML.safe_load(File.read(ARGV[0]))["image"] || {}
    puts [i["uf2"] ? "uf2" : "", i["flash_origin"] ? "flash" : ""].join(" ")' "$chipdir/chip.yaml")
  case "$declared" in
    uf2*) if [ -s "$elf.uf2" ] && [ $(($(size_of "$elf.uf2") % 512)) -eq 0 ]; then ok
          else bad "$board: the family declares UF2 and the build left no whole $elf.uf2"; fi ;;
    *) if [ ! -e "$elf.uf2" ]; then ok; else bad "$board: a UF2 file the family does not declare"; fi ;;
  esac
  case "$declared" in
    *flash)
      sed 's/> RAM AT > CODE/> RAM/' "$BFDIR/platform/common/link.ld" >"$OUT/data-in-ram.ld"
      if cmp -s "$BFDIR/platform/common/link.ld" "$OUT/data-in-ram.ld"; then bad "$board: the .data control changed nothing"
      else
        again ram link,image --link-runtime "$OUT/data-in-ram.ld"
        if [ "$rc" -eq 1 ] && grep -q 'a loaded segment at 0x[0-9a-f]* ([0-9]* bytes) is outside the flash' "$OUT/ram-$board.log" &&
           [ ! -e "$alt.bin" ] && [ ! -e "$alt.uf2" ]; then ok
        else bad "$board: .data stored in RAM: expected a refusal naming the address and no image file (exit $rc)"; cat "$OUT/ram-$board.log" >&2
        fi
      fi ;;
  esac

  # what the port directory controls build on: the first board that got here
  if [ -z "${P_BOARD:-}" ]; then
    P_BOARD=$board P_FILE=$file P_CHIPDIR=$chipdir P_ARCH=$arch P_ELF=$elf
    P_LIBC=$libc P_BUILTINS=$builtins P_RUNTIME=$runtime
  fi

  # 7. the flash image before and after
  if [ -z "$BEFORE" ]; then
    skip "$board: no PORT_BARE_FULL_BEFORE to compare the image with"
    return 0
  fi
  old="$OUT/before-$board.elf"
  rm -rf "$old" "$old.d"
  rc=0
  BAREMETAL_PICOLIBC="$libc" BAREMETAL_BUILTINS="$builtins" "$BEFORE" build --runtime "$runtime" --board "$board" \
    "$HERE/fixtures/hello.rb" "$old" >"$OUT/before-$board.log" 2>&1 || rc=$?
  # exit 64 with the board's name: that driver has no such board
  if [ "$rc" -eq 64 ] && grep -q -- "--board" "$OUT/before-$board.log"; then
    skip "$board: the driver before has no such board"
    return 0
  fi
  [ "$rc" -eq 0 ] || { bad "$board: the build before failed (see $OUT/before-$board.log)"; return 0; }
  if cmp -s "$old.bin" "$elf.bin"; then ok
  else
    bad "$board: the flash image changed: $(cmp -l "$old.bin" "$elf.bin" 2>/dev/null | wc -l | tr -d ' ') bytes differ," \
        "$(wc -c <"$old.bin" | tr -d ' ') bytes before and $(wc -c <"$elf.bin" | tr -d ' ') after"
  fi
}

# 8. Port directories, on the first board that was built. A port directory
# holds board files and chip families laid out as beside the driver.
port_controls() {
  board=$P_BOARD; libc=$P_LIBC; builtins=$P_BUILTINS
  family=$(basename "$P_CHIPDIR")
  pbuild() { # NAME ARGS...: a build of the board as $OUT/NAME-<board>.elf, the status in $rc
    name=$1; shift
    alt="$OUT/$name-$board.elf"
    rc=0
    BAREMETAL_PICOLIBC="$libc" BAREMETAL_BUILTINS="$builtins" "$BF" build --runtime "$P_RUNTIME" "$@" \
      "$HERE/fixtures/hello.rb" "$alt" >"$OUT/$name-$board.log" 2>&1 || rc=$?
  }

  # the family in two places: the first directory's is used, the driver says
  # so, and a copy gives the same ELF file wherever it is
  rm -rf "$OUT/port-same" "$OUT"/same-dir-"$board".elf*; mkdir -p "$OUT/port-same/chip"
  cp -R "$P_CHIPDIR" "$OUT/port-same/chip/$family"
  pbuild same-dir --board "$board" --port-dir "$OUT/port-same"
  if [ "$rc" -eq 0 ] && cmp -s "$P_ELF" "$alt" &&
     grep -qF "chip $family: using $OUT/port-same/chip/$family, not $P_CHIPDIR" "$OUT/same-dir-$board.log" &&
     [ "$(awk -F '\t' '$1 == "chip" { print $2 }' "$alt.d/found")" = "$OUT/port-same/chip/$family" ]; then ok
  else bad "$board: the family in two places: expected the copy to be used and said, and the same ELF file (exit $rc)"; cat "$OUT/same-dir-$board.log" >&2
  fi
  # ... and a later step that finds another family than the build's directory was made from is refused
  pbuild same-dir --board "$board" --steps link,image
  if [ "$rc" -eq 2 ] && grep -q "run step values again" "$OUT/same-dir-$board.log"; then ok
  else bad "$board: a later step with other port directories: expected exit 2, got $rc"; cat "$OUT/same-dir-$board.log" >&2
  fi

  # a board that names a family no port directory holds
  rm -rf "$OUT/port-orphan"; mkdir -p "$OUT/port-orphan/board"
  sed 's/^chip: .*/chip: no-such-family/' "$P_FILE" >"$OUT/port-orphan/board/orphan.yaml"
  pbuild orphan --board orphan --port-dir "$OUT/port-orphan"
  if [ "$rc" -eq 1 ] && grep -qF "no chip/no-such-family/chip.yaml in $OUT/port-orphan, " "$OUT/orphan-$board.log" &&
     grep -qF "$BFDIR" "$OUT/orphan-$board.log" && [ ! -e "$alt" ]; then ok
  else bad "$board: a family no directory holds: expected a refusal naming the directories searched (exit $rc)"; cat "$OUT/orphan-$board.log" >&2
  fi

  # a family outside the repository is held to the contract like one in it:
  # a global the contract does not name is refused
  rm -rf "$OUT/port-stray" "$OUT"/stray-"$board".elf*; mkdir -p "$OUT/port-stray/chip"
  cp -R "$P_CHIPDIR" "$OUT/port-stray/chip/$family"
  printf '\nvoid port_stray(void) {}\n' >>"$OUT/port-stray/chip/$family/chip.c"
  pbuild stray --board "$board" --port-dir "$OUT/port-stray"
  if [ "$rc" -ne 0 ]; then bad "$board: the family with one more global did not build"; cat "$OUT/stray-$board.log" >&2
  else
    set -- --tier full --part program="$alt.d/app.o" --part runtime="$P_RUNTIME" \
      --part builtins="$builtins" --part libc="$libc/lib/libc.a" --image "$alt" --map "$alt.map"
    for o in "$alt.d"/plat-*.o; do [ -f "$o" ] && set -- "$@" --part base="$o"; done
    for o in "$alt.d"/chip-*.o; do [ -f "$o" ] && set -- "$@" --part chip="$o"; done
    rc=0
    "$RUBY" "$CHECK" --contract "$CONTRACT" "$@" --arch "$P_ARCH" >"$OUT/control-$board.log" 2>&1 || rc=$?
    expect "a family outside with a global of its own" "stray: chip exports port_stray"
  fi

  # a directory that is no port directory
  mkdir -p "$OUT/port-none"
  pbuild none --board "$board" --port-dir "$OUT/port-none"
  if [ "$rc" -eq 64 ] && grep -q "is not a port directory" "$OUT/none-$board.log"; then ok
  else bad "$board: a directory with neither board/ nor chip/: expected exit 64, got $rc"
  fi
}

while IFS='	' read -r b f fam c; do lane "$b" "$f" "$fam" "$c" </dev/null; done <"$OUT/boards.tsv"
if [ -n "${P_BOARD:-}" ]; then port_controls; else skip "the port directory controls: no board was built"; fi
finish
