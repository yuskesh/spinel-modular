#!/bin/sh
#
# tests/port-contract/run.sh -- the port contract's checker, on a control
# build made with the host's LLVM alone (no C library, no board).
#
#   LLVM_PREFIX=/opt/llvm-23.1.1 sh tests/port-contract/run.sh
#
# The control build under fixtures/ has the parts of a bare-metal image (a
# program, a runtime archive, a C library, the port's base, a chip and a link
# script) and its own contract, whose names are not the shipped contract's:
# tools/platform/port-check takes every name from the file it is given.
#
# What it establishes, in order:
#
#   1. The shipped contract (tools/platform/port-contract.yaml) is well
#      formed, names nothing twice, and has menus.yaml's tier lattice.
#   2. The control build is accepted, with and without its optional symbol and
#      section, and on both of the fixture's architectures.
#   3. The report says what the image used. A call from a section the link
#      drops is not a use, although the same object's symbol table has it.
#   4. Each control is refused, for its reason and no other, and gets no
#      report:
#        a use the contract does not name;
#        a chip that omits a required symbol;
#        a chip with a global of its own;
#        a chip that calls into the runtime;
#        a chip that refers to the runtime from code this image drops;
#        a reference from a section only the script's KEEP holds;
#        a weak reference to a symbol the image has;
#        a use of another part's hidden symbol;
#        a base that shadows a C library function no row gives it;
#        a link script without the weakly referenced constructor bounds,
#        two of which the linker then defines by itself;
#        a name of the link script's that a part defines instead;
#        an image with no entry;
#        a base without its vector section;
#        a capability of another architecture; a capability above the tier;
#        an image and map of another build than the parts.
#   5. A malformed contract and a bad command line are exit 2 with their own
#      message, never a pass; a report of an earlier accepted run does not
#      survive a refusal.
#
# The fixtures are compiled for thumbv6m-none-eabi: clang needs no sysroot to
# compile freestanding C, so this runs wherever the LLVM release does. The
# real boards are tests/port-contract/boards.sh.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HERE="$ROOT/tests/port-contract"
FIX="$HERE/fixtures"
CHECK="$ROOT/tools/platform/port-check"
RUBY="${RUBY:-ruby}"

die() { echo "port-contract: $*" >&2; exit 2; }
[ -n "${LLVM_PREFIX:-}" ] || die "set LLVM_PREFIX to the official LLVM 23.1.1; this script refuses to guess"
CLANG="$LLVM_PREFIX/bin/clang"
LLD="$LLVM_PREFIX/bin/ld.lld"
AR="$LLVM_PREFIX/bin/llvm-ar"
NM="$LLVM_PREFIX/bin/llvm-nm"
for t in "$CLANG" "$LLD" "$AR" "$NM"; do [ -x "$t" ] || die "no $t"; done
command -v "$RUBY" >/dev/null 2>&1 || die "no ruby at '$RUBY'"

W=$(mktemp -d "${TMPDIR:-/tmp}/port-contract.XXXXXX")
trap 'rm -rf "$W"' EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*" >&2; }

CFLAGS="--target=thumbv6m-none-eabi -mthumb -ffreestanding -Os -ffunction-sections -fdata-sections -Wall -Werror"

# build NAME [-DCTL_...]... : the control build with those controls, in $W/NAME
build() {
  name=$1; shift
  d="$W/$name"
  mkdir -p "$d"
  for part in program runtime libc libc_len base chip; do
    # shellcheck disable=SC2086
    "$CLANG" $CFLAGS "$@" -c "$FIX/$part.c" -o "$d/$part.o"
  done
  "$AR" rcs "$d/librt.a" "$d/runtime.o"
  "$AR" rcs "$d/libc.a" "$d/libc.o" "$d/libc_len.o"
  "$CLANG" -E -P -x c "$@" "$FIX/link.ld" -o "$d/link.ld"
  "$LLD" --gc-sections -T "$d/link.ld" "$d/program.o" "$d/base.o" "$d/chip.o" \
    --start-group "$d/librt.a" "$d/libc.a" --end-group -Map "$d/image.map" -o "$d/image.elf" 2>"$d/link.err" ||
    { cat "$d/link.err" >&2; die "the control build $name did not link"; }
}

# check NAME ARCH TIER [extra port-check arguments]: exit status in $rc,
# stdout and stderr in $W/NAME/out
check() {
  name=$1; arch=$2; tier=$3; shift 3
  d="$W/$name"
  rc=0
  "$RUBY" "$CHECK" --contract "$FIX/contract.yaml" --arch "$arch" --tier "$tier" \
    --part program="$d/program.o" --part runtime="$d/librt.a" --part libc="$d/libc.a" \
    --part base="$d/base.o" --part chip="$d/chip.o" --image "${IMAGE:-$d/image.elf}" \
    --map "${IMAGE_MAP:-$d/image.map}" --report "$d/report.json" "$@" >"$d/out" 2>&1 || rc=$?
}

accept() { # LABEL NAME ARCH TIER
  check "$2" "$3" "$4"
  if [ "$rc" -eq 0 ] && [ -s "$W/$2/report.json" ]; then ok
  else bad "$1: expected acceptance and a report, got exit $rc"; cat "$W/$2/out" >&2
  fi
}

refuse() { # LABEL NAME ARCH TIER COUNT TEXT
  check "$2" "$3" "$4"
  if [ "$rc" -eq 1 ] && grep -qF -- "port-check: refused: $6" "$W/$2/out" &&
     grep -qxF "port-check: refused ($5)" "$W/$2/out" && [ ! -e "$W/$2/report.json" ]; then ok
  else bad "$1: expected exactly $5 refusal(s) with '$6' and no report, got exit $rc"; cat "$W/$2/out" >&2
  fi
}

unable() { # LABEL TEXT then a command that must exit 2 and say TEXT
  label=$1; text=$2; shift 2
  rc=0
  "$@" >"$W/unable.out" 2>&1 || rc=$?
  if [ "$rc" -eq 2 ] && grep -qF -- "$text" "$W/unable.out"; then ok
  else bad "$label: expected exit 2 and '$text', got $rc"; cat "$W/unable.out" >&2
  fi
}

# ---- 1. the shipped contract
SHIPPED="$ROOT/tools/platform/port-contract.yaml"
if "$RUBY" "$CHECK" --contract "$SHIPPED" --list >"$W/shipped.tsv" 2>"$W/shipped.err" && [ -s "$W/shipped.tsv" ]; then ok
else bad "the shipped contract does not load"; cat "$W/shipped.err" >&2
fi
if "$RUBY" -ryaml -e '
  a = YAML.safe_load(File.read(ARGV[0]))["tiers"]
  b = YAML.safe_load(File.read(ARGV[1]))["tiers"]
  abort "tiers differ: #{a.inspect} and #{b.inspect}" unless a == b && a.is_a?(Array)
' "$SHIPPED" "$ROOT/tools/platform/menus.yaml"; then ok
else bad "port-contract.yaml and menus.yaml disagree about the tiers"
fi
# The checker has no name of its own. The control build's contract, whose
# symbols and sections are nearly all other names than the shipped one's, is
# the proof by use; this is the proof by reading:
# with its comments removed, port-check has no symbol or section name of the
# shipped contract as a word, and no part name as a string or a word list's
# item. Part names, and the three symbol names that are also Ruby methods the
# tool calls (File.write, File.read, open), are English words its messages
# and code use, so those are looked for only where a name would be data.
sed -e 's/^[[:space:]]*#.*$//' "$CHECK" >"$W/check.code"
"$RUBY" -ryaml -e 'puts YAML.safe_load(File.read(ARGV[0]))["parts"].keys' "$SHIPPED" >"$W/shipped.parts"
: >"$W/names.in.checker"
{ cut -f5 "$W/shipped.tsv" | sed 's/^/s /'; sed 's/^/p /' "$W/shipped.parts"; } | while read -r kind n; do
  q=$(printf '%s' "$n" | sed 's/[.$]/\\&/g')
  case "$kind $n" in
    p\ * | "s write" | "s read" | "s open") pat="[\"':]$q[\"']|[\"':]$q\$|%[wi]\\[[^]]*\\b$q\\b" ;;
    *) pat="(^|[^A-Za-z0-9_.@:])$q([^A-Za-z0-9_(]|\$)" ;;
  esac
  if grep -qE -- "$pat" "$W/check.code"; then echo "$n" >>"$W/names.in.checker"; fi
done
if [ ! -s "$W/names.in.checker" ]; then ok
else bad "port-check spells contract names itself: $(tr '\n' ' ' <"$W/names.in.checker")"
fi
# ... and the reading can fail: a copy with two names planted is caught
{ cat "$W/check.code"; echo 'HARD = %w[bf_putc write]'; echo 'x = "chip"'; } >"$W/check.planted"
n=0
for pat in '(^|[^A-Za-z0-9_.@:])bf_putc([^A-Za-z0-9_(]|$)' '%[wi]\[[^]]*\bwrite\b' '["'"'"':]chip["'"'"']'; do
  grep -qE -- "$pat" "$W/check.planted" && n=$((n + 1))
done
[ "$n" -eq 3 ] && ok || bad "the name guard does not see planted names ($n of 3)"

# ---- 2. the control build is accepted
build plain
accept "plain build" plain one full
cp "$W/plain/report.json" "$W/plain.report.json"
accept "plain build, other architecture" plain two full
build optional -DCTL_OPTIONAL -DCTL_BOOT
accept "optional symbol and section supplied" optional one full
build lock -DCTL_LOCK
accept "architecture's capability used on it" lock one full
build clock -DCTL_CLOCK
accept "a program that reads the clock" clock one full

# ---- 3. the report
if "$NM" -u "$W/plain/runtime.o" | grep -qw t_never; then ok
else bad "the precision control is empty: runtime.o does not reference t_never"
fi
if "$RUBY" -rjson -e '
  r = JSON.parse(File.read(ARGV[0]))
  o = JSON.parse(File.read(ARGV[1]))
  errs = []
  want = ->(what, got, exp) { errs << "#{what}: #{got.inspect}, expected #{exp.inspect}" unless got == exp }
  want.("format", [r["format"], r["version"], r["verdict"], r["arch"], r["tier"]],
        ["spinel-port-report", 1, "accepted", "one", "full"])
  sym = r["capabilities"].values.flat_map { |c| c["symbols"] || [] }.to_h { |s| [s["name"], s] }
  want.("t_out users", sym["t_out"]["used_by"], ["runtime"])
  want.("t_main users", sym["t_main"]["used_by"], ["base"])
  want.("t_reset users", sym["t_reset"]["used_by"], ["link"])
  want.("t_ram_top users", sym["t_ram_top"]["used_by"], ["base"])
  want.("t_ctors_start users", sym["t_ctors_start"]["used_by"], ["libc"])
  want.("t_hex users", sym["t_hex"]["used_by"], ["chip"])
  want.("t_time users", sym["t_time"]["used_by"], [])       # nothing calls rt_now
  want.("t_time in image", sym["t_time"]["in_image"], false)
  want.("t_hz users", sym["t_hz"]["used_by"], [])           # its only caller is t_time
  want.("t_hz supplied", sym["t_hz"]["supplied"], true)
  want.("linker name users", sym["__init_array_start"]["used_by"], ["libc"])
  want.("shadowed", r["shadowed"], {})
  cs = JSON.parse(File.read(ARGV[2]))["capabilities"].values.flat_map { |c| c["symbols"] || [] }.to_h { |s| [s["name"], s] }
  want.("t_time users (clock build)", cs["t_time"]["used_by"], ["runtime"])
  want.("t_hz users (clock build)", cs["t_hz"]["used_by"], ["base"])
  want.("t_us supplied", sym["t_us"]["supplied"], false)
  want.("t_lock applies", r["capabilities"]["locks"]["applies"], true)
  want.("entry", r["inputs"]["image"]["entry"], ["t_reset"])
  want.("ambient", r["ambient"], { "libc" => { "base" => ["c_init"], "runtime" => ["c_len"] } })
  want.("vectors", r["capabilities"]["start"]["sections"].map { |s| [s["name"], s["supplied"], s["image_bytes"]] },
        [[".t_vectors", true, 8], [".t_boot", false, 0]])
  errs << "t_never is reported" if File.read(ARGV[0]).include?("t_never")
  os = o["capabilities"].values.flat_map { |c| c["symbols"] || [] }.to_h { |s| [s["name"], s] }
  want.("t_us supplied (optional build)", os["t_us"]["supplied"], true)
  want.("boot section (optional build)", o["capabilities"]["start"]["sections"].last["image_bytes"], 16)
  abort errs.join("\n") unless errs.empty?
' "$W/plain.report.json" "$W/optional/report.json" "$W/clock/report.json"; then ok
else bad "the report does not say what the control build used"
fi
check plain one full
if cmp -s "$W/plain.report.json" "$W/plain/report.json"; then ok; else bad "two runs wrote different reports"; fi
check plain two full
if "$RUBY" -rjson -e 'c = JSON.parse(File.read(ARGV[0]))["capabilities"]["locks"]
     exit(c["applies"] == false && !c.key?("symbols") ? 0 : 1)' "$W/plain/report.json"; then ok
else bad "a capability of another architecture is reported as applying"
fi

# ---- 4. the controls are refused
build undeclared -DCTL_UNDECLARED
refuse "undeclared requirement" undeclared one full 1 "undeclared: runtime uses t_extra from base; the contract does not name it"
build omit -DCTL_OMIT
refuse "chip omits a symbol" omit one full 1 "missing: chip does not define t_hz (clock)"
build stray -DCTL_STRAY
refuse "chip with a stray global" stray one full 1 "stray: chip exports chip_private_counter"
build reach -DCTL_REACH
refuse "chip calls something undeclared" reach one full 2 "undeclared: chip uses rt_emit from runtime; the contract does not name it"
build latent -DCTL_CHIP_LATENT
refuse "chip refers to the runtime from dropped code" latent one full 1 "undeclared: chip refers to rt_emit; the contract does not name it"
build kept -DCTL_KEPT
refuse "reference from a section only KEEP holds" kept one full 1 "undeclared: program uses t_secret from base; the contract does not name it"
build weak -DCTL_WEAK -DCTL_CLOCK
refuse "weak reference to a symbol the image has" weak one full 1 "undeclared: base uses rt_now from runtime; the contract does not name it"
build hidden -DCTL_HIDDEN
refuse "use of a hidden symbol of another part" hidden one full 1 "undeclared: base uses rt_hidden from runtime; the contract does not name it"
build shadow -DCTL_SHADOW
refuse "base shadows a C library function" shadow one full 1 "undeclared: runtime uses c_len from base; the contract does not name it"
build noctors -DCTL_NO_CTORS
refuse "link script without the constructor bounds" noctors one full 4 "missing: no line of the link script defines t_ctors_start (constructors)"
if "$NM" "$W/noctors/image.elf" | grep -qw __init_array_start &&
   grep -qF "missing: no line of the link script defines __init_array_start (constructors)" "$W/noctors/out"; then ok
else bad "the linker's own __init_array_start is not in the control image, or was taken for the script's"
fi
build owntop -DCTL_OWN_TOP
refuse "a part defines the link script's name" owntop one full 1 "missing: no line of the link script defines t_ram_top (start); the image's is base's"
build noentry -DCTL_NO_ENTRY
refuse "image with no entry" noentry one full 1 "unresolved: the image's entry point is no global symbol of a part"
build novectors -DCTL_NO_VECTORS
refuse "base without its vector section" novectors one full 1 "missing: base has no section .t_vectors (start)"
refuse "capability of another architecture" lock two full 1 "undeclared: program uses t_lock from base; capability locks does not apply"
refuse "capability above the tier" clock one arena 2 "undeclared: base uses t_hz from chip; capability clock does not apply"
# the parts of one build with the image and map of another
mkdir -p "$W/other"
cp "$W/stray/"*.o "$W/stray/"*.a "$W/other/"
( cd "$W/other" && "$LLD" --gc-sections -T "$W/stray/link.ld" program.o base.o chip.o \
    --start-group librt.a libc.a --end-group -Map image.map -o image.elf )
IMAGE="$W/other/image.elf" IMAGE_MAP="$W/other/image.map"
refuse "image and map of another build" plain one full 5 "unlisted: the image links program.o, which was given to no part"
IMAGE="$W/clock/image.elf" IMAGE_MAP="$W/plain/image.map"
check plain one full
if [ "$rc" -eq 2 ] && grep -qF "is not the map of" "$W/plain/out"; then ok
else bad "a map of another image: expected exit 2, got $rc"; cat "$W/plain/out" >&2
fi
unset IMAGE IMAGE_MAP

# ---- 5. what cannot be checked is not a pass
mutate() {
  sed "$1" "$FIX/contract.yaml" >"$W/$2.yaml"
  if cmp -s "$FIX/contract.yaml" "$W/$2.yaml"; then bad "mutation $2 changed nothing"; fi
}
malformed() { unable "malformed contract ($1)" "$2" "$RUBY" "$CHECK" --contract "$W/$1.yaml" --list; }
mutate 's/names: \[t_putc\]/names: [t_putc, t_out]/' twice
malformed twice "symbol t_out is named more than once"
mutate 's/from: chip, to: \[base\], names: \[t_hz\]/from: board, to: [base], names: [t_hz]/' nopart
malformed nopart "from must be a part"
mutate 's/from: base, to: \[hosted\], names: \[t_lock\]/from: libc, to: [hosted], names: [t_lock]/' ambient
malformed ambient "an ambient part (libc) needs no contract"
mutate 's/arch: \[one\]/arch: [three]/' noarch
malformed noarch "arch must be all or a list"
mutate 's/^version: 1/version: 2/' version
malformed version "version must be 1"
mutate 's/^  locks:/  clock:/' samekey
malformed samekey "key clock is given twice"
{ cat "$FIX/contract.yaml"; echo 'extras: { tier: full }'; } >"$W/topkey.yaml"
malformed topkey "unknown key extras"
mutate 's/ambient: true/ambient: "true"/' flag
malformed flag "ambient must be true or false"
mutate 's/surface: closed/surface: open/' surface
malformed surface "surface, when given, must be closed"
expect2() { # LABEL TEXT: the last check must have been exit 2 saying TEXT
  if [ "$rc" -eq 2 ] && grep -qF -- "$2" "$W/plain/out"; then ok
  else bad "$1: expected exit 2 and '$2', got $rc"; cat "$W/plain/out" >&2
  fi
}
check plain three full; expect2 "unknown architecture" "--arch three"
check plain one huge; expect2 "unknown tier" "--tier huge"
check plain one full --part chip="$W/plain/absent.o"; expect2 "missing file" "no such file"
check plain one full --part board="$W/plain/chip.o"; expect2 "unknown part" "--part board"
check plain one full --report "$W/plain/image.elf"; expect2 "report over an input" "--report names an input"
unable "a part without files" "no file given for part runtime" "$RUBY" "$CHECK" --contract "$FIX/contract.yaml" \
  --arch one --tier full --part program="$W/plain/program.o" --image "$W/plain/image.elf" --map "$W/plain/image.map"
check clock one full
[ "$rc" -eq 0 ] && [ -s "$W/clock/report.json" ] || bad "the clock build is no longer accepted"
check clock one arena
if [ "$rc" -eq 1 ] && [ ! -e "$W/clock/report.json" ]; then ok
else bad "a report of an accepted run survived a refused run (exit $rc)"
fi

echo "port-contract: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
