# tools/platform: the platform ledger and the port contract

## The ledger

`menus.yaml` is the ledger a platform-first target profile expands through.
A profile under `tools/freestanding/profiles` may name a platform, an
architecture and what the platform supplies instead of spelling every target
fact out; `spinel-fs-emit` reads this file to find the base profile and the
platform calls that combination allows
([tools/freestanding](../freestanding/README.md)).

`tests/freestanding/profiles/test_profile_reader.rb`, run by
`sh tests/freestanding/run.sh`, reads every shipped profile and emits a
kernel for each platform-first one.

## The port contract

`port-contract.yaml` names every symbol and section that crosses between the
parts of a bare-metal build of a whole program: the program and the runtime,
the C library and the compiler's builtins, the port's common code (`base`),
the chip family and board code (`chip`), and the link script (`link`). Each
name is under a capability (`start`, `console`, `clock`, ...) with the lowest
tier that needs it and the architectures it exists on
([guide](../../docs/platform/port-contract.md),
[design](../../docs/platform/port-contract-design.md)).

`port-check` holds one build to that file:

```sh
tools/platform/port-check --contract tools/platform/port-contract.yaml \
  --arch armv8-m.main --tier full \
  --part program=app.o --part runtime=libspinel_rt_bare.a \
  --part builtins=libclang_rt.builtins-armv8m.main.a --part libc=libc.a \
  --part base=plat-start.o --part base=plat-posix.o --part base=plat-atomic-v6m.o \
  --part chip=chip-chip.o \
  --image app.elf --map app.elf.map --report app.port-report.json
```

- It measures the image, not a model of the link: the map (`ld.lld -Map`)
  says which input sections the link kept and which file each symbol of the
  image comes from, and the relocations of a kept section say what it refers
  to. Every file the image links must be given to a part, and a part may be
  given several files.
- It needs `llvm-nm`, `llvm-readobj` and `llvm-readelf` (`LLVM_PREFIX`, or
  `NM`, `READOBJ`, `READELF`) and Ruby.
- Exit 0: accepted, and the report (`spinel-port-report`, version 1) says
  which part used each name in this image. Exit 1: refused, one
  `port-check: refused: <kind>: ...` line per reason (`undeclared`,
  `missing`, `stray`, `unlisted`, `unresolved`) and no report. Exit 2: the
  check could not be made.
- `port-check --contract FILE --list` prints the contract as a table.

The checker has no symbol, section or part name of its own. A new name in
the agreement is a line in `port-contract.yaml`.

`sh tests/port-contract/run.sh` runs the checker on a control build made with
the host's LLVM alone, with the controls that must be refused.
`sh tests/port-contract/boards.sh DIR` holds real builds to the board schema
and the contract when the cross toolchain is present: every board that has a
board file in `tools/bare-full/board/`.

## Board files

A board is values, not code: `board/<name>.yaml` beside a port's code says
which chip family the board has and gives the family the values it asks for
(a crystal frequency, a flash size, which UART is the console), plus the
policy values every board has (stack size, the collector's settings).
`board-schema.yaml` states the form, version 1, and the policy keys; a chip
family states its own keys in `chip/<family>/chip.yaml`.

```sh
tools/platform/board-check --schema tools/platform/board-schema.yaml \
  --chip-dir CHIP-DIR --contract tools/platform/port-contract.yaml board/NAME.yaml
```

Exit 0: valid. Exit 1: refused, one `board-check: refused: ...` line per
reason. Exit 2: the check could not be made. `--values` prints every value
of a valid board as `key<TAB>value`, and `--head` its name, chip family,
core and architectures. An integer of a board file is plain decimal. A chip
family's statement may also carry `objects` and `image`, which say how a
build of the family is made (`tools/bare-full/README.md`); they are checked
for their form and make no value. The validator has no key, chip or board
name of its own. `sh tests/port-contract/board.sh` holds it to a control
board and the damaged files it must refuse.
