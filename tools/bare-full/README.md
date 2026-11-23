# tools/bare-full: full on a Cortex-M with no RTOS

A Spinel program with the hosted runtime and its collector, linked into one
image for a Cortex-M33 or a Cortex-M0+ with no operating system.
Runs on QEMU's `mps2-an521` (`tests/bare-full/run.sh`) and, run once by hand,
on the FRDM-MCXN947 board (`--board frdm-mcxn947`); that run is recorded in
[docs/platform/board-runs.md](../../docs/platform/board-runs.md). These two
are the boards kept here: `an521` is the reference, and `frdm-mcxn947` has no
other home yet. A board or a chip family for another chip is kept by its
users in a port directory of their own (`--port-dir`, below).

## What it needs

| Variable | What |
|---|---|
| `LLVM_PREFIX` | the official LLVM 23.1.1 (clang, lld, llvm-ar) |
| `BAREMETAL_PICOLIBC` | picolibc 1.8.12 built with it for the board's core: [installation record](../../docs/toolchains/picolibc-1.8.12/INSTALLATION-RECORD.md) |
| `BAREMETAL_BUILTINS` | compiler-rt's builtins for the board's core: [installation record](../../docs/toolchains/compiler-rt-23.1.1/INSTALLATION-RECORD.md) |
| `SPINEL_DIR` | optional; the Spinel checkout, by default `vendor/spinel`, which must be built |

and `qemu-system-arm` to run the image. On Debian 13 the LLVM release's `lld`
also needs `LD_LIBRARY_PATH` to name ICU 70 (see the picolibc record).

## Use

```sh
tools/bare-full/spinel-bare-full runtime /path/to/rt
tools/bare-full/spinel-bare-full build --runtime /path/to/rt/libspinel_rt_bare.a \
  app.rb app.elf
qemu-system-arm -machine mps2-an521 -cpu cortex-m33 -m 16 -display none \
  -monitor none -serial stdio -kernel app.elf
```

`runtime` compiles the pinned runtime once (38 objects, about 6 s). `build`
compiles `app.rb` with `--cc` naming the target's clang, so Spinel takes the
target's 32-bit word, and links it with the base (`platform/common`) and the
board's chip family. Work files
go to `app.elf.d/`, the link map to `app.elf.map` and the flash image to
`app.elf.bin`; for a chip family that declares the format, `app.elf.uf2` is
written too. `--heap-kb N` caps the heap; without it the heap is all the
RAM between `.bss` and the stack (64 KB on an521, 32 KB on the FRDM
board: each board's `policy.stack_bytes`).

`--board NAME` names a board file, `board/NAME.yaml` (default `an521`), and
the file names its chip family, `chip/FAMILY/`. Both are looked for in the
*port directories*: those given with `--port-dir DIR` (may repeat), then
those of `BAREMETAL_PORT_PATH` (separated by `:`), then this directory. A
port directory has `board/` or `chip/` or both; one that has neither is
refused. The board and its family are searched for separately, each from
the start, and when more than one directory holds one the driver says which
it used. `spinel-bare-full boards [--port-dir DIR]...` lists the boards
found: name, board file, family, family's directory, separated by tabs. The
whole behaviour is in
[the board file's guide](../../docs/platform/board-file.md#where-boards-and-chip-families-are-found).

`--set KEY=N` overrides one integer value of
the board file by its key path for this build, for example
`--set policy.stack_bytes=16384`. The key must be one the chip family lists
for its boards (`board:` in its `chip.yaml`) or a `policy.` value; anything
else is refused with exit 64, and so is a key whose value is a name
or a number outside the rule `chip.yaml` gives for that key
(`min`, `max`, `one_of`). The driver checks nothing else: it does not check
the board file itself or a `policy.` value, and a value the chip code cannot
serve stops the build at an `#error`.

For the FRDM-MCXN947, build with `--board frdm-mcxn947` and write
`app.elf.bin` at 0x10000000 with LinkServer, as
`tests/freestanding/frdm-host.sh` writes the bare-frdm lane's image; the console is
the MCU-Link VCOM at 115200 8N1.

For a board with a Cortex-M0+, build the runtime with `runtime --cpu m0plus`
(`build` refuses a runtime made for another core), with picolibc and the
builtins built for that core. No board kept here has one; the control board
of `tests/port-contract/boards.sh` is built for it and never run.

The console prints `BAREFULL<TAB>BEGIN`, the program's output, then
`BAREFULL<TAB>GC<TAB><collections>` and `BAREFULL<TAB>EXIT<TAB><status>`, and
the core stops in a loop: stop reading after the `EXIT` line. A fault prints
`BAREFULL<TAB>FATAL<TAB>fault`. The FRDM board also prints
`BAREFULL<TAB>CLOCK<TAB><Hz>` and the registers that show the core clock,
right after `BEGIN`.

## The steps of a build

`build` is six steps in a fixed order. Each reads what the steps before it
left in `app.elf.d/` and writes there.

| Step | Reads | Writes (in `app.elf.d/` unless said) |
|---|---|---|
| `values` | `board/<name>.yaml`, `chip/<family>/chip.yaml`, `--set` | `bf-board.h`, `found` |
| `program` | `app.rb`, Spinel, `runtime/`, the C library's headers | `app.c`, `spinel.log`, `app.o`, `objects.program` |
| `platform` | `platform/common/*.c`, `chip/<family>/*.c`, `bf-board.h` | `plat-<name>.o`, `chip-<name>.o`, `objects.platform` |
| `objects` | the program `chip.yaml` names with `objects`, the board file, `bf-board.h` | what that program makes (`chip-*.o`), `objects.objects` |
| `link` | the three `objects.*` lists, the link parts, `bf-board.h`, the runtime archive, the builtins, the C library, `--heap-kb` | `link-chip.ld`, `link-runtime.ld`, `link-add-<n>.ld`, `link.log`; `app.elf`, `app.elf.map` |
| `image` | `app.elf`, `chip.yaml`'s `image` | `app.elf.bin`; `app.elf.uf2` when the family declares it |

`--steps LIST` (names separated by commas) runs only those steps, with the
same other arguments, on what an earlier run left: `--steps link,image`
links again without compiling. A step that does not find an earlier step's
output stops with exit 2 and names the step to run; an unknown name is
exit 64. `--steps` trusts the work directory: it does not notice that a
source changed since the step that compiled it. A value given with `--set`
reaches the build in the `values` step, so name that step too. A step that
finds another board file or chip family than the `values` step recorded in
`found` stops with exit 2.

`objects.program`, `objects.platform` and `objects.objects` are text files,
one object per line: what each step made, in link order. The link reads the
three and links exactly those, in that order: the program, the base's
objects sorted by name, the chip family's sorted by name, then the objects
the family made itself. The order is part of the image. One more object in
the link is one more line in a list, followed by `--steps link,image`.

### The link script's parts

The link script is two files, each passed through the C preprocessor with
`bf-board.h` and given to the linker as a script of its own, in this order:

1. **the chip family's part**, `chip/<family>/link.ld`: the memory regions.
   It must declare one named `CODE`, where the image is stored and run from,
   and one named `RAM`. A family whose boot ROM wants a block in front of
   the image places it before the vector table here.
2. **the runtime's part**, `platform/common/link.ld`, the same for every
   family: the order of the sections and every symbol the base and the C
   library read from the script, `__image_end` among them (one past the last
   byte of the image in flash).

The board's values are the third part; they have no file of their own and
reach both through the header.

| Option | Effect |
|---|---|
| `--link-chip FILE` | FILE in place of the chip family's part |
| `--link-runtime FILE` | FILE in place of the runtime's part |
| `--link-add FILE` (may repeat) | FILE as one more part after the two, in the order given |

A part that adds a section says where it goes with the linker's own
`INSERT BEFORE` or `INSERT AFTER` and a section the runtime's part names, as
the tests' control family does for `.boot2`
(`tests/port-contract/fixtures/boards/chip/tchip/link.ld`);
`tests/port-contract/fixtures/user-part.ld` is a twelve-line example. A part of the user's may use the `BF_...` values.

Two things about the layout that a program may rely on are the runtime's
part's to keep. The vector table is 16 words; the part asserts it at every
link. `.data` and every `.data.*` section are stored in `CODE` and copied to
`RAM` at reset, so a function a program puts in a `.data.*` section runs
from RAM.

### The image formats

The `image` step writes the flat image `app.elf.bin`, and `app.elf.uf2` for
a family whose `chip.yaml` has `image: { uf2: { family_id: N } }`: UF2 with
256 bytes in each 512-byte block, every loaded segment at its load address.

`image.flash_origin` and `image.flash_bytes` say what the family's flash is.
Each is a number or the name of one of the build's values (`chip.<path>`,
`board.<path>`, `policy.<key>`), so the range is not stated a second time.
With them, a segment loaded outside the flash stops the step before any
format is written, and the message names the address: a replaced link part
that stores `.data` in RAM would otherwise give a flat image of hundreds of
megabytes and a UF2 that boots nothing.

## Layout

- `spinel-bare-full`: the driver.
- `runtime/`: what the Spinel runtime and the generated program are compiled
  with on a target with no operating system. `defines` is the list of
  defines, one per line; `shim/` holds stand-ins for the POSIX headers
  picolibc does not have (from Spinel's own headers for wasm32-wasi, MIT,
  with additions; `shim/LICENSE.spinel`); `force.h` is included into every
  compile and declares what the runtime expects and picolibc leaves out.
- `platform/common/link.ld`: the runtime's part of the link script.
- `platform/common/start.c`: the vector table, start-up, `_exit` and the fault
  handler. The start-up runs `.init_array`, where the runtime installs its
  `inspect` hooks.
- `platform/common/atomic-v6m.c`: the `__atomic_*` calls ARMv6-M needs, with
  interrupts masked; atomic on one core only.
- `platform/common/posix.c`: `getenv` (the slab off, the first collection at
  16 KB), `write` to the UART, `clock_gettime` from SysTick or from the
  board's microsecond counter (`bf_board_us`, where a chip family has one),
  `nanosleep` on that clock, and the calls the
  runtime references but this platform does not have, failing with `ENOSYS`.
- `chip/<family>/`: a chip family's code. `chip.c` has the console, the core
  clock and the early register write the reset entry makes (none on an521;
  the RAM blocks' clocks on the MCX N947); `link.ld` is the family's part of
  the link script, the memory map;
  `chip.yaml` names the core (`cpu`), gives the family's own values (`values`:
  where flash and RAM are and how large), lists the values a board of this
  family states (`board`) and may say how a build is made: `objects` names a
  program of the family that makes objects before the link, and `image` says
  what the flash is and which formats are made. `an521` and `mcxn947`.
  `chip.c` is one translation unit:
  splitting or reordering it changes the flash image.
- `board/<name>.yaml`: a board. Values only, no code: the chip family
  (`chip`), what the board wires (the crystal, which UART or Flexcomm and
  which pins) and the `policy`
  group (the stack size, the collector's slab and first-collection settings
  and, where a board uses less RAM than the family has, `ram_bytes`).
  Integers are plain decimal with the unit in the key. A board names
  instances ("UART 0"), not addresses: the chip code holds the table from
  instance to address, lists only instances whose values have a cited source,
  and refuses any other at compile time. `an521` and `frdm-mcxn947`.

A new board on a chip family that is here is a new file in `board/`. A new
chip family is a new directory in `chip/` with the three files above. Either
may be in a port directory outside this repository instead; the base, the
runtime's part of the link script and `runtime/` are always this
directory's.

The driver runs a family's `objects` program as
`ruby chip/<family>/<objects> --board BOARD.yaml --header bf-board.h --out
app.elf.d -- CC FLAG...`. It prints the objects it made, one path per line
on its standard output; each must be a `chip-*.o` in `app.elf.d`.

### How a value reaches the code

The driver reads the board file and its chip family's `chip.yaml` and writes
`app.elf.d/bf-board.h`: one `#define` per integer value, in plain decimal,
named from the key path in upper case with `.` as `_`.

| Where the value is | Define | Example |
|---|---|---|
| `chip.yaml`, under `values` | `BF_CHIP_<PATH>` | `values.ram.bytes` is `BF_CHIP_RAM_BYTES` |
| the board file's `policy` group | `BF_POLICY_<KEY>` | `policy.stack_bytes` is `BF_POLICY_STACK_BYTES` |
| any other group of the board file | `BF_BOARD_<PATH>` | `clock.crystal_hz` is `BF_BOARD_CLOCK_CRYSTAL_HZ` |

The base and the chip family are compiled with `-include` of that
header, and each part of the link script is passed through the C
preprocessor with it (`app.elf.d/link-chip.ld` and `link-runtime.ld` are
the scripts the link uses). No value is passed as a
linker `--defsym`, so a board value adds no symbol to the image; `--heap-kb`
keeps its `--defsym=__bf_heap_bytes`. Everything derived from a value (a baud
divisor, a start-up delay) is a constant expression in the chip code; nothing
is computed at run time. A value that is a name, not a number, makes no
define: it is for the family's `objects` program to read from the board
file, not for the driver.

### The work directory

| File in `app.elf.d/` | What |
|---|---|
| `app.c`, `app.o` | the program |
| `plat-<name>.o` | the base: one per `platform/common/*.c` |
| `chip-<name>.o` | the chip family: one per `chip/<family>/*.c` |
| other `chip-*.o` | what the family's `objects` program made |
| `bf-board.h` | the generated values |
| `found` | the board file and the chip family's directory the build uses |
| `objects.program`, `objects.platform`, `objects.objects` | what each step made, in link order |
| `link-chip.ld`, `link-runtime.ld`, `link-add-<n>.ld` | the link script's parts with the values in place |

## Limits

Integer is 32 bits; no files, processes, signals, threads or `Fiber`; one
program per image, on one core. A Ruby feature links only
when every OS call its runtime parts make is defined by picolibc or
`platform/common/posix.c`: when the program reaches a call to a function
neither defines, the link stops with `undefined symbol`.
`String#crypt` stops (libc's `crypt(3)`, which picolibc lacks); `Marshal` and
`Digest` link. Sockets, `fcntl` and `poll` are defined only to fail with
`ENOSYS`, so that a polymorphic call that can reach them, such as `<<` on a
boxed value, still links. `sh tests/bare-full/run.sh` is
the check, on QEMU and for the Cortex-M33 only; the boards have no lane.
