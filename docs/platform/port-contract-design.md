# The port contract: design

A `full` program on a microcontroller with no operating system is one image
linked from parts that different people write: the compiled program, the
Spinel runtime, a C library, the compiler's builtins, start-up and OS-call
code, a chip's clock and console code, and a link script. This page says how
this repository divides that work, what it writes down about the division,
and what it checks. The guides say how to use each piece:

- [the port contract](port-contract.md): the names that cross between the
  parts, and the checker;
- [the board file](board-file.md): a board as values, and a chip family's
  statement;
- [changing a bare-metal build](changing-a-build.md): the link script's
  parts, the build's steps and the image formats;
- [`tools/bare-full`](../../tools/bare-full/README.md): the build itself.

## The division

| Layer | Holds | Where |
|---|---|---|
| architecture | compile flags, the reset entry, the vector table, the ARMv6-M atomics | `tools/bare-full/platform/common`, with the next layer |
| what the runtime asks | the OS calls the runtime and the C library reach, the symbols the start-up reads from the link script | `tools/bare-full/platform/common` (the **base**), and the runtime's part of the link script |
| chip family | memory regions, the boot ROM's needs, clocks, the console, time, the image formats | `tools/bare-full/chip/<family>/` |
| board | a crystal, a flash size, which UART is the console: values only | `tools/bare-full/board/<name>.yaml` |

Three rules follow from it.

- **A board is data.** It has no function and supplies no symbol. A board
  that seems to need code is a chip family missing a value or a table.
- **A chip family owns what its chip's boot needs and nothing of the
  runtime's.** It supplies a handful of functions to the base, uses three
  of the base's, and exports nothing else.
- **Start-up belongs to one part.** The base goes from reset through `.data` and
  `.bss`, calls the chip family, starts the runtime and calls the program.
  No setting lets a build choose who does that.

The same four layers are where other embedded language implementations
draw their lines. Those that wrote down what the runtime asks of a port
have ports that live outside the main repository; those that kept a board
as checked data have added boards without editing the core.

## What is written down

The agreement between the parts is a data file,
[`tools/platform/port-contract.yaml`](../../tools/platform/port-contract.yaml).
It names every symbol and section that crosses from one part to another,
once, under a capability that states the lowest tier that needs it, the
architectures it exists on, the part that supplies it and the parts that
may use it.

Why a file of its own:

- **A header cannot say it.** A C header declares functions. It cannot say
  which part supplies a symbol, cannot name a symbol of the link script or
  a section, cannot say "only on ARMv6-M", and declaring a function does
  not stop a part from calling one that is not declared.
- **A target profile's list of externs is too flat.** The freestanding
  route states its platform surface as one list for one platform and
  architecture, supplied by "the platform". A `full` image has seven
  parties, and one list of names applies to several architectures with
  exceptions.
- **The checker holds no names.** `tools/platform/port-check` has no
  symbol, section or part name of its own. A refusal is always the result
  of a lookup in the file, never a condition in code, so adding to the
  agreement is an edit to one file. The tests hold this two ways: they
  run the checker on a control build whose contract has fifteen symbol and
  section names the shipped one lacks, and they read the checker's source
  with its comments removed and find no symbol, section or part name of
  the shipped contract in it as data, with a planted copy to show that the
  reading can fail.

Four properties of the file carry most of its weight.

- **A required name must be defined by its supplier whether or not the
  program uses it.** The verdict on a port is then the same for every
  program. It is also the only way to catch a link script without the init
  array bounds: the C library reads those through weak references, so the
  link succeeds and the constructors silently never run.
- **A chip family's surface is closed.** Every global it defines and every
  symbol it leaves undefined must be a name the file gives it, in all of
  its files, whatever the program uses. A chip that calls into the runtime
  from code this image happens to drop is still refused.
- **Sections cross too.** The vector table and a chip's boot block reach
  the link script by section name; the boot block's object has no symbol
  at all.
- **The link script supplies a name only when a line of a script defines
  it.** A default the linker supplies by itself does not count: lld
  defines `__init_array_start` when a script does not.

## What the contract does not hold

Some of the agreement is not a symbol or a section.

| Agreement | What holds it |
|---|---|
| the vector table is 16 words, first in the code region | a check in the runtime's part of the link script, at every link |
| `.data` and every `.data.*` section are stored in flash and copied to RAM at reset | the runtime's part of the link script states it; no test |
| a loaded segment is inside the flash | the build's `image` step, where a chip family states its flash range; every family here does |
| the order of the objects in the link | the build writes it to list files and links exactly those |
| call order: the early register write before any RAM is used, the console's set-up after `.data` and `.bss` and before the constructors, the chip's report after `BEGIN` | the base's code; nothing checks a port against it |
| the hardware state a chip family leaves when the program starts (which clocks run from what, which blocks are out of reset, a running timer, the other cores asleep) | nothing; a program's drivers rely on it |
| the console's lines (`BAREFULL<TAB>BEGIN`, `GC`, `EXIT`, `FATAL`, `CLOCK`) | `tests/bare-full/run.sh` reads them for one board |
| how the C library was built | its installation record; nothing checks the options |

## How a crossing is measured

`port-check` reads the image, not a model of the link. The linker's map
lists every input section the link kept, with the file it came from, and
every symbol with the file that defines the copy in the image; the
relocations of a kept section name what it refers to. A reference from a
kept section of one part to a global the image takes from another part is
a crossing. So a section the link dropped asks for nothing, a section only
the script's `KEEP` holds is counted, a weak reference counts when the
image has the symbol, a hidden symbol counts, and of two definitions the
one counted is the one linked.

Two simpler measures give wrong answers:

- A relocatable link of a part keeps whole archive members, and a hello
  program then appears to need about 70 socket, directory and process
  functions that the image never links.
- Linking each part alone the way the image is linked is a model of the
  link. It misses each case of the paragraph above, and the linker answers
  `__bss_start` and the init array bounds by itself in such a link, so
  they never show as undefined.

## A board's values

A board file and its chip family's statement are held to a schema by
`tools/platform/board-check`, which, like the contract's checker, has no
key, chip or board name of its own.

- **A value is stated once.** Everything that follows from it is derived
  in the chip family's code. One value is kept raw: `an521`'s console
  divisor, which follows from no real baud rate.
- **A board names instances, not addresses.** The table from an instance
  to its registers is the family's, and holds only instances whose values
  have a cited source; any other stops the compile.
- **A value travels one way.** The build writes one header of defines from
  the two files, and the base, the chip family, what the family's own
  program compiles and every part of the link script are compiled with it. No value is a
  linker symbol, so a board file cannot change what crosses in the
  contract, and the board lane compares the header with what the validator
  reads, so the two readers of a file cannot drift apart.
- **Derived values are constant expressions.** Nothing is computed or
  formatted at run time; a report line that holds a value is one string
  constant.
- **Policy is not hardware.** The stack size, the RAM a program is given
  and the collector's settings are the same keys for every chip.

## Where a board and a chip family are kept

The driver takes a board file and a chip family from *port directories*:
any the user names, then its own. A port directory outside this repository
is laid out as the one inside.

**A chip family is kept with the people who use the chip.** This
repository keeps the contract, the checker, the base and two families:
`an521`, the reference, which a suite runs under QEMU with no hardware,
and `mcxn947`, which has no other home yet. A family for any other chip is
a port directory of its users'.

- **A family outside is held exactly as one inside.** There is one
  contract, one checker and one board lane, and none of them asks where a
  family's directory is. The lane builds one family from a port directory
  that is not the driver's on every run.
- **The user's directory wins, and the build says so.** A board or a family
  found in more than one place is taken from the first, with a line naming
  both. What a build was made from is written beside it, and a later step
  that would find something else is refused.
- **A path that is wrong stops the build.** A named directory that is no
  port directory is never passed over in favour of the files here.
- **The board and its family are found separately**, so a project can add
  a board to a family here, or bring its own family for a board here.
- **Only the board file and the family move.** The base, the runtime's
  part of the link script and the runtime's defines are the driver's. A
  family outside therefore depends on a revision of this repository: on the
  contract's names and on the base that supplies them.
- **An image does not depend on where the family is.** The family's
  directory is replaced by a fixed name in what the compiler records.

## The build

- **Six named steps**, each reading what the ones before left in the work
  directory. A step can be run alone.
- **The link script is two files and the header**, given to the linker as
  one script each: the chip family's (memory regions, and what its boot
  ROM needs in front of the image) and the runtime's (the sections, their
  order, and every symbol the contract's `link` part supplies; one file
  for every chip). A chip's boot block and a user's own section are placed
  by the linker's `INSERT`, naming a section of the runtime's part. Joining
  the parts with the preprocessor's `#include` also works; it needs a hole
  cut in advance wherever a section may ever be added, and `INSERT` needs
  none.
- **The link order is a file.** The order of objects is part of the image:
  the same functions linked in another order are another image.
- **A chip family's own objects are made by a program the family names.**
  A chip whose boot ROM checks a block in front of the image makes that
  block, checksum included, there: before the link, since the block is
  part of the image.
  The driver has no knowledge of any chip's boot scheme.
- **Image formats are a chip family's declaration.** The flat image is
  always written; a UF2 where the family gives its family id.

## The checks, and what they measure

| Check | What it holds |
|---|---|
| `tests/port-contract/run.sh` | the checker, on a control build with a contract of its own made with the host's LLVM alone: the build is accepted, and sixteen damaged builds are each refused for their own reason and no other |
| `tests/port-contract/board.sh` | the board file's validator, on a control board and damaged files |
| `tests/port-contract/boards.sh` | every board the driver finds, in this repository, in the port directories the caller names and in the lane's own control port directory: the file is valid; the validator and the driver find the same family; the generated header equals what the validator reads; the build holds to the contract; three damaged contracts or architectures are refused; a step alone, a replaced link part, an added link part, a changed value and a segment outside the flash each behave as the guide says; and, given an older driver, the flash image is byte-identical to that driver's. Once a run: a family in two places, a family in none, a later step under another path, a family outside with a global of its own, and a directory that is no port directory |
| `tests/bare-full/run.sh` | whole programs for `an521` under QEMU print their expected output |

None of them runs an image on a board;
[runs on boards](board-runs.md) lists what has been run by hand.

Facts these checks and the builds behind them establish:

- **A build is reproducible bit for bit**, the ELF file included, from the
  same program, runtime archive, C library and builtins. That is what
  makes a byte comparison mean anything. No path of the checkout reaches
  an object.
- **How much of the contract a program uses.** A hello uses 39 of the 55
  names that apply on `an521`, 42 of 55 on `frdm-mcxn947` and 45 of 91 on
  the lane's Cortex-M0+ control board. The rest are names the base must
  still define.
- **The link order is part of the image.** Linking one board's chip code
  before the base's instead of after it moves 1,140 of a 192,756-byte
  flash image: the same functions at other addresses.
- **So is the division of code into files.** Moving one function group of
  the base into a file of its own changes the size of a function that
  calls across the new boundary, and moves about 83% of the bytes of every
  flash image. This is why the base's three files still mix architecture
  code with the port of the runtime.
- **A user's link part costs what it adds.** A part with 16 bytes in a
  section of its own makes the flash image exactly 16 bytes longer.
- **A changed value shows where it should.** Halving a board's stack
  changes one byte of the flash image and two symbols, on every board the
  lane builds.
- **A link that stores `.data` in RAM is stopped** before any image file is
  written, on every board the lane builds. Without the check the flat image would be
  hundreds of megabytes long.
- **A UF2 is written exactly when the family declares it**: for the
  control board's hello, 742 blocks, 379,904 bytes. No test here decodes
  the file and compares it with the flat image.

## Not built

- **A generic board** whose values come from the command line. A board is
  a file in a port directory.
- **A chip of another architecture.** Everything here is Arm: Cortex-M33
  and Cortex-M0+. A RISC-V core needs its own start-up, atomics, C library
  build and builtins.
- **A chip whose boot ROM wants an image definition block** in place of a
  checksummed second stage.
- **An early-initialisation hook** through which a chip family's clock and
  console bring-up could be supplied by the same code as a program's
  drivers. Today that knowledge exists once in a chip family's C and again
  in any driver library for the chip.
- **A tier below `full`.** The contract's tier field exists; no `arena` or
  `core` program has been built this way, so every capability is `full`.
- **The base divided by layer.** See the fact above.
- **The runtime's member list as data.** The driver finds it by matching
  one line of Spinel's `Makefile`.

## Not known

- **Whether a larger program asks for a name the base lacks.** Every name
  the base supplies to another part is in the contract, used or not. A
  program that reaches a call the base does not define at all is a link
  error or a refusal; how often that happens is not known.
- **What a port-neutral naming would be.** The names are the build's own,
  `bf_` prefix included, and five capabilities (`files`, `sockets`,
  `contexts`, `signals`, `mappings`) exist only because the runtime keeps
  those calls reachable. Whether a port may leave one out is undecided.
- **What must move the contract's version.** A new required name breaks
  every existing chip family; a new optional one does not.
- **Whether a shadowing definition should need a declaration.** One that
  another part uses must be given by a row. One that only its own part
  uses, and the builtins shadowing the C library's memory functions, are
  reported and constrained by nothing.
- **Names of the runtime's own.** The program's entry and the collector's
  counter that the base reads are the compiler's and the runtime's names;
  a move of the Spinel pin can rename them, and the contract then has to
  follow.
- **What the runtime's defines select.** The runtime is compiled as for a
  target with no processes, sockets or second stacks; which of those paths
  a bare-metal image depends on has not been traced.
- **What `bf_core_hz` means.** It is the rate SysTick counts. Where a
  family gives a constant, it is false once a program changes the system clock,
  which is why a chip family may also supply a microsecond counter.
- **Sections of a program's own C code.** The scripts name the sections
  the measured programs have; another would be placed by the linker's
  orphan rules, unseen.
- **Another linker.** Only the pinned lld has been given several scripts
  and `INSERT`.
- **macOS.** Nothing here has been run on it.
