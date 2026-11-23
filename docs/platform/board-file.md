# The board file

Status: the form of a board file and of a chip family's statement is fixed
(version 1) and a validator holds files to it. The board files kept in
this repository are in [`tools/bare-full/board`](../../tools/bare-full/board);
their keys are listed under [the boards kept here](#the-boards-kept-here).
The examples here are the control board of the tests, whose names are not
those of any real board.

A **board** is values: a crystal frequency, a flash size, which UART the
console is on. It has no code. A **chip family** is code (clocks, console,
time, the chip's own sections) and says which values a board of that family
gives. In [the port contract](port-contract.md) the chip family is the part
`chip`; a board is not a part and supplies no symbol.

- **Schema:** [`tools/platform/board-schema.yaml`](../../tools/platform/board-schema.yaml)
- **Validator:** [`tools/platform/board-check`](../../tools/platform/board-check)
- **Checks:** [`tests/port-contract/board.sh`](../../tests/port-contract/board.sh)

## Three files

| File | Who writes it | What it says |
|---|---|---|
| `tools/platform/board-schema.yaml` | this repository | the head every board file and chip statement has, the kinds of rule, and the policy keys, which are the same for every chip |
| `chip/<family>/chip.yaml` | the chip family, beside its code | the architectures and core of the family, the family's own values, and every key a board of the family gives, with what each may be |
| `board/<name>.yaml` | whoever has the board | the chip family, the values, and the policy |

The validator has no key, chip or board name of its own. A new board value
is a line in the family's `chip.yaml`; a new policy value is a line in the
schema.

`chip/` and `board/` are the two directories of a *port directory*.
`tools/bare-full` is one, and a project may keep another anywhere:
[where boards and chip families are found](#where-boards-and-chip-families-are-found).

## A board file

```yaml
format: spinel-board
version: 1
chip: tchip
clock: { crystal_hz: 12000000 }
console: { uart: 0, baud: 115200 }
flash: { boot: plain }
policy:
  stack_bytes: 32768
  gc_threshold_kb: 16
  gc_slab: 0
```

- **The name is the file's name.** `board/tboard.yaml` is the board
  `tboard`; there is no `name` key. A board's name has no architecture in
  it: the chip family lists its architectures.
- **`format` and `version`** are the schema's. Another version is refused,
  never read on a guess.
- **`chip`** names the family. The validator reads
  `<chip-dir>/<family>/chip.yaml`; a family with no statement is refused.
- **The groups** (`clock`, `console`, `flash` here) are the family's. A
  board gives exactly the keys its family lists: a key the family does not
  list is refused, and so is a listed key left out, unless the family marks
  it optional.
- **Every value is an integer or a name.** An integer is plain decimal with
  its unit in the key (`_hz`, `_bytes`, `_kb`). `2M` and `12MHz` are
  refused, and so are `0x10`, `010` (which YAML reads as eight) and
  `1_000`: every reader of the file must read the same number. A chip
  family's own values may be written in hexadecimal; they are addresses.
- **Instances, never addresses.** A board says "the console is UART 0". The
  table from an instance to its registers, clock gate and reset bit is the
  family's code.
- **A value is stated once.** What follows from it (a baud divisor from the
  crystal and the baud rate, a start-up delay from the crystal) is derived
  by the family, not written beside it. One exception is known: `an521`
  gives `console.baud_divisor: 16`, the register value as written, because
  16 follows from no real baud rate at that board's 25 MHz (115200 baud
  would be 217), and deriving it would change the image.

### Policy

`policy` is not the board's hardware. It is how much of it a program is
given, and the keys are the same for every chip:

| Key | Meaning | Rule |
|---|---|---|
| `stack_bytes` | the reset stack, at the top of RAM | integer, at least 1024 |
| `ram_bytes` | RAM used, when not all of the chip's | integer, at least 1024; optional |
| `gc_threshold_kb` | the collector's first collection | integer, at least 1 |
| `gc_slab` | the collector's slab arena, off or on | 0 or 1 |

A board file carries the defaults for its board.

## A chip family's statement

```yaml
format: spinel-chip
version: 1
archs: [armv6-m]
cpu: m0plus
values:
  ram: { origin: 536870912, size_bytes: 65536 }
board:
  clock.crystal_hz: { type: int, min: 1000000, max: 15000000 }
  console.uart:     { type: int, one_of: [0, 1] }
  console.baud:     { type: int, min: 300 }
  flash.boot:       { type: name, one_of: [plain, quad], optional: true }
```

- **`archs`** are architecture names of the port contract. With
  `--contract`, an architecture the contract does not have is refused.
- **`cpu`** is the core the family is built for.
- **`values`** are the family's own: facts of the chip that no board
  changes, such as where RAM is.
- **`objects`** and **`image`**, both optional, say how a build for the
  family is made: a program of the family that makes objects before the
  link, and what the flash is and which image formats are written
  ([changing a bare-metal build](changing-a-build.md)).
- **`board`** is a flat map from a dotted key path to a rule. A rule is
  `{type: int, min:, max:, one_of: [...]}` or `{type: name, one_of: [...]}`;
  `optional: true` lets a board leave the key out.

Both files are read strictly. An unknown key is refused, and a key given
twice cannot be read at all: YAML would keep the last of the two without a
word.

A chip statement is refused (exit 1) for an unknown top-level key, a wrong
head, architectures that are not a list or not the contract's, a `cpu` that
is not a name, or a family value that is not an integer or a name. A
statement whose `board` map is itself unusable is exit 2, the check could
not be made: a board key that is one of the schema's own (`format`,
`version`, `chip`, `policy`), a rule with no type, a name rule without
`one_of`, an unknown rule key, or a key path that is not lower-case dotted
names.

## Checking a board file

```sh
tools/platform/board-check --schema tools/platform/board-schema.yaml \
  --chip-dir CHIP-DIR --contract tools/platform/port-contract.yaml \
  board/NAME.yaml
```

It needs Ruby only. `CHIP-DIR` is a directory of chip families (a port
directory's `chip/`), not a port directory: the validator reads no board
directory. `--chip-dir` may be given several times, and the family's
statement is then the first `CHIP-DIR/<family>/chip.yaml` in the order
given. A family none of them holds is refused with every place looked at:

```
board-check: refused: chip tchip has no statement at A/tchip/chip.yaml, B/tchip/chip.yaml
```

| Exit | Meaning |
|---|---|
| 0 | valid |
| 1 | refused; one `board-check: refused: ...` line per reason |
| 2 | the check could not be made: usage, a missing file, a file that cannot be read, a key given twice, a malformed rule in a chip statement, a malformed schema. Never a pass |

`--head` prints one line for a valid board: its name, its chip family, the
family's core, the family's architectures and the family's directory as an
absolute path, tab-separated.

`--values` prints every value of a valid board, one `key<TAB>value` line
each: `board.<path>` for the board's, `policy.<path>`, and `chip.<path>` for
the family's own.

```
board.clock.crystal_hz	12000000
board.console.uart	0
board.console.baud	115200
board.flash.boot	plain
policy.stack_bytes	32768
policy.gc_threshold_kb	16
policy.gc_slab	0
chip.ram.origin	536870912
chip.ram.size_bytes	65536
```

A build that turns the files into compiler defines can be compared with
this list, so that the validator and the build cannot read a file two ways.

## The boards kept here

A chip family is kept with the people who use the chip, in a port directory
of theirs. This repository keeps two: `an521`, the reference family, which
is the one a suite runs (under QEMU, with no hardware), and `mcxn947`,
which is here because it has no other home yet.

The RP2040 family and the Raspberry Pi Pico's board file, `rp2040-pico`,
are kept in [spinel-pico](https://github.com/yuskesh/spinel-pico), under
its `port/` directory, and are built by naming that directory with
`--port-dir` ([where boards and chip families are found](#where-boards-and-chip-families-are-found)).

These are the board files in `tools/bare-full/board`, with their chip
families in `tools/bare-full/chip`. They are valid under `board-check`,
which `tests/port-contract/boards.sh` runs on each. Every board also has the three policy keys
`stack_bytes`, `gc_threshold_kb` and `gc_slab`.

| Board | Chip family | Keys the board gives |
|---|---|---|
| `an521` | `an521` | `clock.core_hz`, `console.uart`, `console.baud_divisor` |
| `frdm-mcxn947` | `mcxn947` | `console.flexcomm`, `console.port`, `console.rx`, `console.tx`, `console.mux`, `console.baud` |

- A value may be a name, not a number: the control board's `flash.boot`
  is one of the names its family lists. A name makes no define; it is for
  a family's `objects` program to read from the board file. The control
  family's program reads none.
- The FRDM board gives no crystal. Its family reads the core clock the
  boot ROM left.
- An instance a family has no table entry for (a second UART, another
  Flexcomm) is refused twice: by the family's rule (`one_of: [0]`) and by
  the family's code at compile time. No hardware fact was added that the
  code did not already use.
- Each family's own values are its memory: `flash.origin`, `flash.bytes`,
  `ram.origin`, `ram.bytes`. A family whose boards differ in flash size
  leaves the size to the board.

### How a build uses the values

bare-full's driver reads the two files and writes one header of
`#define`s, one per integer value: `BF_BOARD_<PATH>` for a board's value,
`BF_POLICY_<KEY>` for a policy value, `BF_CHIP_<PATH>` for a family's own,
the path in upper case with `_` for `.`. The header is given to the base's
and the family's code, to what the family's `objects` program compiles, and to the link
script, which is preprocessed. The driver holds no value name; it walks the
maps.

- No value becomes a symbol of the image, so a board file cannot change
  what crosses in the port contract.
- Every derived value is a constant expression in the family's code.
  Nothing is computed at run time.
- `--set KEY=N` on the driver's command line overrides one value by its
  key path (`--set policy.stack_bytes=16384`). It is read in the build's
  `values` step ([changing a bare-metal build](changing-a-build.md)). The driver holds such a value to the chip family's rule for the key, and
  refuses a key the family does not list. A `policy.` value is taken as
  given: its rules are the schema's, and `board-check` does not see the
  command line.

`board-check --values` prints the same paths, and
`tests/port-contract/boards.sh` compares the generated header with it for
every board, so the two readers of a file cannot drift apart.

## Adding a board


1. Find the chip family, and read its `chip.yaml` for the keys a board
   gives.
2. Write `board/<name>.yaml` with the head, `chip`, those keys, and
   `policy`, in a port directory of your own or in `tools/bare-full`. Start
   from a board of the same family. The name is lower-case letters, digits
   and `-`.
3. Run `board-check`.
4. Build, and hold the build to [the port contract](port-contract.md) with
   `port-check`. A board file changes no symbol, so a board of a family
   that passes should pass.

A board that seems to need code does not get a function in its file. It
means the family is missing a value or a table; if it truly is code, it is
one optional hook, and that is a change to the port contract first.

## Where boards and chip families are found

A **port directory** holds board files as `board/<name>.yaml` and chip
families as `chip/<family>/` (`chip.yaml`, the sources, `link.ld`, and
whatever the family's `objects` names), either or both. The driver's own
directory, `tools/bare-full`, is one. A project keeps its own wherever it
likes, laid out the same way, and names it to the driver:

```sh
tools/bare-full/spinel-bare-full build --port-dir /path/to/port \
  --board myboard --runtime RT/libspinel_rt_bare.a app.rb app.elf
```

| Given by | Form |
|---|---|
| `--port-dir DIR` | one directory; may be given several times |
| `BAREMETAL_PORT_PATH` | directories separated by `:`; an empty entry is passed over |

- **The order searched** is the `--port-dir` directories as given, then
  the variable's in order, then the driver's own. A directory named twice
  is searched once.
- **A board** is the first `board/<name>.yaml` in that order. **Its chip
  family** is searched for separately, in the same order from the start:
  the first `chip/<family>/chip.yaml`. So a board file of your own may name
  a family that is here, and a family of your own replaces the one of the
  same name here for every board that names it.
- **When more than one directory holds the board or the family**, the
  driver says on its standard error which it used, and builds:

  ```
  spinel-bare-full: chip an521: using A/chip/an521, not B/chip/an521
  ```

- **When none holds it**, the driver stops and names the directories it
  searched. For a board that is exit 64, with the boards those directories
  do hold; for a family a board file names, exit 1:

  ```
  spinel-bare-full: --board myboard: no board/myboard.yaml in A, B (the boards there: an521, frdm-mcxn947)
  spinel-bare-full: A/board/myboard.yaml names chip "mychip"; no chip/mychip/chip.yaml in A, B
  ```

- **A directory that is no port directory** (it has neither `board/` nor
  `chip/`, or does not exist) stops the driver before anything is searched,
  exit 64 for the option and 2 for the variable. A mistyped path does not
  fall back to the files here without a word.
- **`spinel-bare-full boards [--port-dir DIR]...`** prints the boards the
  port directories hold, one line each, sorted by name: the name, the board
  file, the chip family the file names, and that family's directory (empty
  when no port directory holds it), tab-separated. It needs no toolchain.
- **What a build was made from is recorded.** The `values` step writes
  `OUT.elf.d/found`, two lines: `board<TAB>FILE` and `chip<TAB>DIRECTORY`.
  A later run of other steps (`--steps`) that finds another board file or
  family than the record's is refused, exit 2.

Only the board file and the family come from a port directory. The base,
the runtime's part of the link script and the runtime's defines are the
driver's, wherever the family is.

A family kept outside this repository is held to
[the port contract](port-contract.md) exactly as one kept here: the same
`port-check`, the same board lane
([running the checks](port-contract.md#running-the-checks)). Nothing about
its place makes it trusted more or less, with one thing to know: **a port
directory holds code the build runs.** A family's `objects` program is run
by the driver, with the user's rights.

A build's image does not depend on where the family's directory is: the
family's sources are compiled with their directory's name replaced by
`bare-full/chip/<family>`, so a file name a source keeps (`__FILE__`) is
the same.

There is no generic board whose values come from the command line alone.

## Running the checks

```sh
sh tests/port-contract/board.sh
```

It needs Ruby only, and establishes that

1. the control board is valid, and `--values` prints its values, the
   policy's and the family's;
2. each damaged board file is refused for its reason and no other: a key
   the family does not list, a listed key left out, a value with a unit
   suffix or not in plain decimal, a value out of its range or not among the allowed ones, a policy
   key the schema does not have, another schema version, a chip family with
   no statement;
3. a damaged chip statement is refused (an unknown key, an architecture
   the port contract does not have) or cannot be read, exit 2 (a rule of
   no type, a board key that is the schema's own);
4. what cannot be read is exit 2 with its own message: a key given twice,
   a missing file, a bad command line;
5. with two chip directories, the first that holds the family is the one
   read, in both orders and when the first holds none; a family in neither
   is refused naming both places.

## Limits

- **Form, not truth.** A board file that says 12 MHz for a board with an
  8 MHz crystal is valid. Only a run on the board shows it.
- **Build and link values only.** Pin aliases and what a driver needs are
  not in a board file.
- **The validator's own tests use a control board.** The real board
  files are checked by the board lane, which needs the cross toolchain.
- **A policy value given on the command line is unchecked.** The driver
  holds a `--set` of a board value to the family's rule, but not a
  `policy.` value.
- **No generic board.** A board is a file in a port directory.
- **A family's rules are its own.** Nothing checks that two families name
  the same thing the same way (`clock.crystal_hz` in both).
