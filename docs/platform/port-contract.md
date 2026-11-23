# The port contract

Status: the contract is written down and a checker holds builds to it.
The builds that are checked are made by
[`tools/bare-full`](../../tools/bare-full/README.md), the build of a whole
`full` program for a Cortex-M with no operating system, with its driver
`spinel-bare-full`. [The design](port-contract-design.md) says why the work is divided this
way, what the checks measure, and what is not built.

A `full` program on a microcontroller with no operating system is linked from
several parts written by different people: the compiled program, the Spinel
runtime, a C library, the compiler's builtins, start-up and OS-call code, the
chip's clock and console code, and a link script. The **port contract** is
the list of every symbol and section one of those parts may take from
another, and who supplies it. A new chip is a port: it supplies what the
contract says a chip supplies, uses only what the contract lets a chip use,
and exports nothing else.

- **Contract:** [`tools/platform/port-contract.yaml`](../../tools/platform/port-contract.yaml)
- **Checker:** [`tools/platform/port-check`](../../tools/platform/port-check)
- **Checks:** [`tests/port-contract/run.sh`](../../tests/port-contract/run.sh)
  (host toolchain) and
  [`tests/port-contract/boards.sh`](../../tests/port-contract/boards.sh)
  (real builds of every board that has a board file)

## The parts

The parts are named in the contract file; the checker knows none of them.

| Part | What it is | Today | In the contract |
|---|---|---|---|
| `program` | the object Spinel compiles from the Ruby program | `app.o` | group `hosted` |
| `runtime` | the Spinel runtime and collector, an archive | `libspinel_rt_bare.a` | group `hosted` |
| `libc` | the C library | picolibc 1.8.12 | ambient |
| `builtins` | the compiler runtime | compiler-rt's builtins, built from the LLVM release's sources for the core | ambient |
| `base` | the vector table, start-up, the OS calls the runtime reaches, and on ARMv6-M the atomics | `tools/bare-full/platform/common` | |
| `chip` | the clock, the console, time, and the chip's own sections | a family's `chip/<family>/chip.c` and the objects the family's own program makes (a boot block, say) | surface closed |
| `link` | the link script, in its parts | a family's `chip/<family>/link.ld`, `tools/bare-full/platform/common/link.ld`, and any part a user adds | not files: what a line of a script defines |

- Parts of one **group** use each other freely: the program and the runtime
  are one body of code as far as a port is concerned.
- An **ambient** part may be used by any part without a row. What the C
  library and the builtins themselves ask of the port is still checked.
- **Surface closed**: every global the part defines must be a row's name,
  and every symbol its files leave undefined must be a row's name given to
  it, or an ambient part's. This is held in all of the part's files,
  whatever this program uses: a chip that calls into the runtime from code
  this image happens to drop is still refused. A helper inside a chip must
  be `static`.
- The **link script** supplies a name only when a line of the script
  defines it. A default the linker supplies by itself (lld defines
  `__init_array_start` when the script does not) does not count, and
  neither does a part defining the name.

Every file the image links must be given to a part. The linked image and
its map are inputs of the check, not parts. A **board** is not a part
either: a board is values (a crystal frequency, a flash size, console pins)
and supplies no symbol; [the board file](board-file.md) is its form.

## The contract file

The file is a ledger in the style of [`menus.yaml`](../../tools/platform/menus.yaml):
`format: spinel-port-contract`, `version: 1`, then `tiers`, `archs`, `parts`
and `capabilities`. The reader is strict: an unknown top-level key, a
duplicate key or a flag that is not a boolean is exit 2. A capability has

- `tier`: the lowest tier whose builds need it, on the lattice
  `core < arena < full`. A build of a lower tier is not held to the
  capability and may not use it. Every capability is `full` today: no other
  tier has been built for a bare microcontroller, and the file claims
  nothing that was not measured;
- `arch`: `all`, or the architectures it exists on. Elsewhere its names may
  be neither used nor required;
- `symbols` and `sections`: rows of `{from, to, names, optional}`. `from` is
  the part that supplies the names, `to` the parts or groups that may use
  them.

A boundary between two parts is nothing more than the rows that connect
them. Every name appears once. The sections named are the ones a part must
hand the link script by name; which other sections a part has is not held.

**A required name must be defined by its supplier whether or not this
program uses it.** The verdict on a port is then the same for every program.
It is also what catches a link script without the init array bounds: the C
library reads those through weak references, so the link succeeds and the
program's constructors silently never run.

`optional: true` lets the supplier leave the names out; the users must cope
(a weak reference). Today that is `bf_board_us`, the section `.boot2`, and
the four bounds `__preinit_array_start/_end` and `__init_array_start/_end`,
which the scripts define and nothing in the link reads.

| Capability | What crosses | Architectures |
|---|---|---|
| `start` | the entry, the bounds of `.data` and `.bss`, the stack top, the chip's early register write, the program's `main`; sections `.vectors` and, optionally, `.boot2` | all |
| `constructors` | the init and fini array bounds, from the link script to the C library. Required: `__bothinit_array_start/_end` and `__fini_array_start/_end`, the ones the C library reads | all |
| `heap` | the heap's bounds, from the link script to the C library | all |
| `console` | `write`, `read`, `isatty`; the chip's `bf_console_init` and `bf_putc`; the base's `bf_puts`, `bf_putu`, `bf_putx` for the chip | all |
| `clock` | `clock_gettime`, `nanosleep`; the chip's `bf_core_hz` and optional `bf_board_us` | all |
| `exit` | `_exit`, the collector's count for the last line, the chip's `bf_board_report` | all |
| `environment` | `getenv`, which shadows the C library's | all |
| `files`, `sockets`, `contexts`, `signals`, `mappings` | calls the runtime keeps reachable. The name must exist; the port may answer "not here" (`ENOSYS`, a failed mapping, a signal never delivered) | all |
| `atomics` | the 36 `__atomic_*` calls | ARMv6-M |
| `image` | `__image_end`, from the link script to the program: the load address one past the last byte of the image, the first free byte of flash on a board that runs from flash | all |

That is 91 symbols on ARMv6-M, 55 on ARMv8-M Mainline, and two sections. The
file is the authority; print it as a table with

```sh
tools/platform/port-check --contract tools/platform/port-contract.yaml --list
```

The names are `tools/bare-full`'s own, `bf_` prefix included.

## Checking a build

```sh
tools/platform/port-check --contract tools/platform/port-contract.yaml \
  --arch armv8-m.main --tier full \
  --part program=app.o --part runtime=libspinel_rt_bare.a \
  --part builtins=libclang_rt.builtins-armv8m.main.a --part libc=libc.a \
  --part base=plat-start.o --part base=plat-posix.o --part base=plat-atomic-v6m.o \
  --part chip=chip-chip.o \
  --image app.elf --map app.elf.map --report app.port-report.json
```

- `--arch` is one of the contract's `archs` (`armv6-m`, `armv8-m.main`) and
  `--tier` one of its `tiers`.
- `--map` is the linker's map of the image (`ld.lld -Map`, which bare-full
  writes as `app.elf.map`). A map that is not this image's is exit 2.
- A part may be given several files, and every file the image links must be
  given to some part.
- `--revision REV` records a source revision in the report.
- It needs Ruby, and `llvm-nm`, `llvm-readobj` and `llvm-readelf`: under
  `LLVM_PREFIX/bin`, or named by `NM`, `READOBJ` and `READELF`. It links
  nothing.

| Exit | Meaning |
|---|---|
| 0 | accepted; the report is written |
| 1 | refused; one `port-check: refused: <kind>: ...` line per reason on stderr, and no report |
| 2 | the check could not be made: usage, a missing file or tool, a malformed contract, an unknown architecture, tier or part, a map that is not the image's. Never a pass |

The kinds of refusal:

| Kind | What happened | Example |
|---|---|---|
| `undeclared` | a name crosses that no row gives that supplier, that user, this architecture and this tier; or a part with a closed surface refers, anywhere in its files, to a symbol no row gives it | `runtime uses t_extra from base; the contract does not name it` |
| `missing` | a required name is not defined by its supplier (for the link script: by a line of the script), or the image's definition is another part's; a required section is not in the image | `chip does not define t_hz (clock)` |
| `stray` | a part with a closed surface defines a global the contract does not name | `chip exports chip_private_counter` |
| `unlisted` | the image links a file that was given to no part | `the image links program.o, which was given to no part` |
| `unresolved` | a reference is answered only by the linker's own default, or the image's entry is no global symbol of a part | `the image's entry point is no global symbol of a part` |

A run that is refused also deletes a report left at the `--report` path by
an earlier accepted run.

### How a crossing is measured

From the image, not from a model of the link.

- The map lists every input section the link kept, with the file it came
  from, and every symbol with the file that defines the copy in the image.
- The relocations of a kept section (`llvm-readobj -r` on the same file)
  name the symbols it refers to.
- A reference from a kept section of one part to a global the image takes
  from another part is a crossing. A global the map places in no file and
  a line of the script assigns is the link script's.

So a section the link dropped asks for nothing; a section only the script's
`KEEP` holds is counted; a weak reference counts when the image has the
symbol; a hidden symbol counts; and of two definitions the one counted is
the one linked.

Two ways that do not work, both tried:

- A relocatable link of a part (`ld.lld -r`) keeps whole archive members,
  and a hello program then appears to need about 70 socket, directory and
  process functions that the image never links.
- Linking each part alone as the image is linked
  (`--gc-sections --unresolved-symbols=ignore-all` from the part's roots)
  is a model of the link. It misses each case of the paragraph above, and
  lld answers `__bss_start` and the init array bounds by itself in such a
  link, so they never show as undefined.

## What the contract does not hold

These are part of the agreement between the same parts, are relied on today,
and are checked by nothing. A port has to keep them by hand.

- **Call order.** The reset entry applies `bf_early_write` before anything
  touches RAM, the stack included. `bf_console_init` runs after `.data` is
  copied and `.bss` cleared, and before the C library runs the
  constructors. `bf_board_report` runs after the `BEGIN` line.
- **Hardware state at program start.** What the chip's start-up leaves: the
  clock each tree runs from, which blocks are out of reset, a running timer,
  the console's UART, the other cores asleep. A program's drivers read this
  state instead of setting it. A chip family says what it leaves in its own
  documents; nothing here checks it.
- **Layout.** A 16-word vector table in `.vectors`, first in the code
  region; `.data` and its sub-sections copied to RAM at start-up.
- **The console protocol.** `BAREFULL<TAB>BEGIN`, the program's output,
  `BAREFULL<TAB>GC<TAB>n`, `BAREFULL<TAB>EXIT<TAB>status`; `FATAL` on a
  fault; a chip may print `BAREFULL<TAB>CLOCK<TAB>...` lines after `BEGIN`.
- **One core.** The ARMv6-M atomics mask interrupts and are atomic on one
  core only; a chip with more cores keeps the others asleep.
- **The C library's build.** picolibc is built so that `stdout` goes through
  `write` (`posix-console=true`) with no thread-local storage, no crt and no
  semihosting. Another build crosses different symbols.

## The report

`--report` writes one JSON document for an accepted build. It is what
[the core report](../core/core-report.md) is for a CORE entry: a statement of
what one build did, not of what the contract allows.

| Key | Meaning |
|---|---|
| `format`, `version` | `spinel-port-report`, `1` |
| `verdict`, `arch`, `tier`, `revision` | the result and what was asked |
| `inputs` | the contract, the image (file, sha256, entry), the map, and every part's files with their sha256 |
| `tools.reader` | the tool that read the objects |
| `capabilities` | per capability: `tier`, `arch`, whether it `applies` to this build, and for each symbol and section `name`, `from`, `to`, `optional`, `supplied`, `used_by` and `in_image` |
| `ambient` | what was taken from the ambient parts |
| `shadowed` | names defined twice, with the part whose definition the image took, read from the map. Thirteen today: `getenv` by `base` over `libc`, and twelve `__aeabi_mem*` by `builtins` over `libc` |

`used_by` is exact for this image: a hello on `an521` uses 39 of the 55
names that apply there, and on the lane's Cortex-M0+ control board 45 of
91. An optional name the
supplier left out has `supplied: false`.

A refused build gets no report. A report path that names an input is exit 2.

## Changing the agreement

**Edit the contract file and nothing else.** The checker holds no symbol,
section or part name; `tests/port-contract/run.sh` holds it two ways: the
checker is run on a control build whose contract has fifteen names the
shipped one lacks, and the checker's source, comments removed, is searched
for every name of the shipped contract, with a planted copy to show the
search can fail. If adding a name seems to need a change in `port-check`, the contract's
form is missing something, and that is the change to propose.

- **A part needs one more name from another part.** Add it to a row of the
  capability it belongs to, or add a row or a capability. If the name is
  required, every port must define it from then on, used or not.
- **A name is no longer needed.** Remove it. A chip that still exports it
  is refused as `stray` until it stops.
- **A capability exists on one more architecture.** Add the architecture to
  its `arch`. Do not add a condition anywhere else.
- **A new part.** Add it under `parts` with how it is measured.

A new required name is a change for every chip, inside this repository and
outside it. What must move `version` is not decided; until it is, a
chip family kept outside this repository has to pin a revision of it.

## Porting a chip

A chip family is a directory `chip/<family>/` of a port directory, with
`chip.c`, `link.ld` (the family's part of the link script: its memory
regions) and `chip.yaml`, and a board of it is a
[board file](board-file.md). The port directory is `tools/bare-full` or one
of your own, anywhere
([where boards and chip families are found](board-file.md#where-boards-and-chip-families-are-found)).
What the contract adds is the test: build an
image for a board of the family and run `port-check`, or let
`tests/port-contract/boards.sh` do both. A chip that passes

- defines every required name a row gives `from: chip` (today
  `bf_early_write`, `bf_console_init`, `bf_putc`, `bf_core_hz` and
  `bf_board_report`), whether or not the program reaches it;
- refers, anywhere in its files, only to names whose row lists `chip` in
  `to` (today the base's three console helpers) and to the ambient parts;
- exports no other global;
- is linked with scripts whose own lines define every required name a row
  gives `from: link`. The runtime's part of the script defines them all;
  a family's part needs only the regions `CODE` and `RAM`
  ([changing a bare-metal build](changing-a-build.md)).

Then read [what the contract does not hold](#what-the-contract-does-not-hold):
passing is not everything a port owes.

The test is the same for a family kept outside this repository: put its
port directory in `BAREMETAL_PORT_PATH` and the board lane builds its
boards and holds them to the contract with the ones here. The lane does
this on every run for one family, the control family of its own fixtures,
which is in a port directory that is not the driver's.

## Running the checks

```sh
LLVM_PREFIX=/opt/llvm-23.1.1 sh tests/port-contract/run.sh
sh tests/port-contract/boards.sh DIR
```

`run.sh` needs the LLVM release only: its fixtures are freestanding C
compiled for `thumbv6m-none-eabi`, with no C library and no board. It
establishes, in order, that

1. the shipped contract is well formed, names nothing twice, and has
   `menus.yaml`'s tier lattice;
2. the control build is accepted, with and without its optional symbol and
   section, on both of the fixture's architectures;
3. the report says what the image used, and a call from a section the link
   drops is not a use;
4. each of sixteen controls is refused for its reason and no other, with no
   report:
   - a use the contract does not name; a chip that omits a required symbol;
     a chip with a global of its own; a chip that calls into the runtime;
   - a chip that refers to the runtime from code this image drops; a
     reference from a section only the script's `KEEP` holds; a weak
     reference to a symbol the image has; a use of another part's hidden
     symbol; a base that shadows a C library function no row gives it;
   - a link script without the weakly referenced constructor bounds, two of
     which the linker then defines by itself; a name of the link script's
     that a part defines instead; an image with no entry; a base without
     its vector section;
   - a capability of another architecture; a capability above the build's
     tier; an image and map of another build than the parts;
5. a malformed contract and a bad command line are exit 2 with their own
   message, and the report of an earlier accepted run does not survive a
   refusal.

On Debian 13 the LLVM release's `ld.lld`, which the script uses to link the
control build, needs `LD_LIBRARY_PATH` to name ICU 70.

`boards.sh DIR` builds a hello program with `tools/bare-full/spinel-bare-full`
for every board the driver finds: the lines of `spinel-bare-full boards`.
The lane has no list of boards and no search of its own: it takes each
board's file, chip family and the family's directory from the driver, and
the core and architecture from the files. `DIR` is a scratch directory
outside the checkout.

The port directories are those of `BAREMETAL_PORT_PATH`, to which the lane
appends one of its own, `tests/port-contract/fixtures/boards`: the control
board `tboard` and its family `tchip`, made to be built and never run. It
is a Cortex-M0+ family with an `objects` program, a section inserted before
the vector table and a UF2 declaration, so every run of the lane builds
those parts of the driver and the base for ARMv6-M, from a port directory
outside `tools/bare-full`.

For each board, in order:

1. `board-check`: the [board file](board-file.md) is valid for its family,
   and the validator, given the same directories, finds the family in the
   directory the driver names.
2. The build.
3. The header the build generated from the two files has one define for
   each integer value `board-check --values` prints, with that value, and
   no other: the build and the validator read the files alike. The
   comparison is shown to fail on a changed value and on a dropped one.
4. `port-check`: the build's parts, image and link map hold to the shipped
   contract. The report is left as `<board>.port-report.json` in `DIR`.
5. Three controls show the lane can refuse this build: checked as an
   architecture its chip family does not list, it is refused over the
   atomics; against a copy of the contract without one of the chip's
   console names, the chip is refused for a stray global and the base for
   an undeclared use; against a copy without the constructor bounds' row,
   the C library's use of them is refused.
6. With `PORT_BARE_FULL_BEFORE`, the same program built by that older
   driver gives the same flash image, byte for byte. A board that driver
   does not have is `NOT RUN`.

Once in a run, on the first board built, the lane also shows what the
search does:

- the board's family copied to a second port directory and given with
  `--port-dir` is the one used, the driver says so, `found` names the copy,
  and the ELF file is the same;
- a later step run on that build without the option is refused;
- a board file that names a family no directory holds is refused, the
  message naming the directories searched, and no ELF file is written;
- a copy of the family with one more global function builds, and
  `port-check` refuses it as `stray`;
- a directory that is no port directory is refused.

It reads these variables. `CORE` is a chip family's `cpu` in upper case
(`M33`, `M0PLUS`).

| Variable | What |
|---|---|
| `LLVM_PREFIX` | the LLVM 23.1.1 release |
| `BAREMETAL_PORT_PATH` | optional: port directories outside the repository, separated by `:`, whose boards are built and held with the ones here |
| `PORT_BARE_FULL` | optional: another `spinel-bare-full` driver than this checkout's, in a checkout whose Spinel is built. It must have the `boards` subcommand |
| `PORT_<CORE>_PICOLIBC`, `PORT_<CORE>_BUILTINS` | picolibc's install prefix and the builtins archive for that core |
| `PORT_<CORE>_RUNTIME` | optional: a runtime archive already built, to save the time |
| `PORT_BARE_FULL_BEFORE` | optional: another `spinel-bare-full` driver, of the revision an edit started from. A change that only moves code and values must leave every flash image as it was; with this set, a board whose image differs fails the lane. The older driver need not have board files |

Without them it prints `NOT RUN` with the reason and exits 0; `REQUIRE_ALL=1`
makes that a failure. A core whose variables are missing is not run while
the others are, and the image comparison is `NOT RUN` without
`PORT_BARE_FULL_BEFORE`.

Neither script runs an oracle (a comparison with another implementation),
and neither runs an image.

## Limits

- **Symbols and sections, not behaviour.** A chip that defines `bf_core_hz`
  and returns the wrong rate passes. Running the image is a separate
  check: `tests/bare-full/run.sh` does it for `an521` under QEMU, and
  [runs on boards](board-runs.md) records the runs made by hand.
- **The base's surface, not every program.** Every name the base supplies
  to another part is in the contract, used or not. (The base's exports are
  not closed: it has globals of its own, such as its vector table and
  fault handler, that no row names.) A program that needs a name the base
  lacks altogether, or a crossing between two parts no row connects, is
  refused, and the agreement is then changed on one side or the other. A program
  that wants the end of the image in flash, for one, does not get the
  bounds of `.data`, which are the base's; it gets a name of its own,
  `__image_end`.
- **The link script is one part.** The checker sees it as what the lines
  of the script define. It cannot say which of several script fragments
  supplied a name, and it does not measure the script's own references to
  a part's symbols, other than the entry.
- **Sections are held one way.** The contract names the sections a part
  must hand the script. A part's other sections are not held, and two
  sections of one object with the same name are taken together.
- **Not every shadow needs a row.** A shadowing definition that another
  part uses must be given by a row (the base's `getenv`), and in a part
  with a closed surface a shadow without one is `stray`. A shadow in an
  open part that only that part uses, or nothing uses, is accepted and
  only listed under `shadowed`; so is one ambient part shadowing the other
  (the builtins' `__aeabi_mem*` over the C library's).
- **`full` only.** The tier field exists; no `arena` or `core` program has
  been built this way.
- **Arm only.** Cortex-M33 and Cortex-M0+.
- **No image is run by these checks.** `tests/bare-full/run.sh` runs
  programs for `an521` under QEMU; the other two boards have no lane that
  runs.
