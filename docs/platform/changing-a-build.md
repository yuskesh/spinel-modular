# Changing a bare-metal build

This is the task guide; [`tools/bare-full/README.md`](../../tools/bare-full/README.md)
is the reference for the driver, its work directory and its layout.

`tools/bare-full/spinel-bare-full build --board NAME APP.rb OUT.elf` builds
a whole program for a board, and that one line is all most builds need. This
page is for the build that needs something else: a section of its own in
the image, another memory map, one more object in the link, one step run
again, or an image format a chip family declares. None of it needs an edit
to the driver. A board or a chip family of your own needs no file in this
repository either:
[where boards and chip families are found](board-file.md#where-boards-and-chip-families-are-found).

## The link script is two files and a header

| Part | File | Holds |
|---|---|---|
| the chip family's | `chip/<family>/link.ld` | the memory regions, and what the chip's boot ROM needs in front of the image (a region and a section for a boot block, on a chip that has one) |
| the runtime's | `platform/common/link.ld` | the sections and their order, and every symbol the start-up code and the C library read from the script. The same for every chip |
| the board's values | no file of its own: the generated header `OUT.elf.d/bf-board.h` | the flash size, the stack size, the RAM used ([the board file](board-file.md)) |

The driver runs each part through the C preprocessor with the header, so a
part may use any `BF_BOARD_...`, `BF_POLICY_...` or `BF_CHIP_...` value, and
gives the results to the linker, one `-T` each, in a fixed order: **the chip
family's, the runtime's, then any you add**. The order is forced: the
runtime's part places sections in two memory regions named `CODE` and `RAM`,
which the chip family's part must already have declared.

What the runtime's part asks of a chip family's part is exactly that: a
region `CODE`, where the image is stored and run from, and a region `RAM`.

### Replacing a part

| Option | Effect |
|---|---|
| `--link-chip FILE` | `FILE` in place of the chip family's part |
| `--link-runtime FILE` | `FILE` in place of the runtime's part |
| `--link-add FILE` | `FILE` after the two; may be given several times, kept in order |

A replacement is preprocessed with the header like the part it replaces.
The preprocessed parts are left in the work directory as `link-chip.ld`,
`link-runtime.ld` and `link-add-<n>.ld`, so what the linker was given can
be read afterwards. (The link map does not name them: the linker writes no
script's file name into it.)

A replaced runtime's part still owes the build everything the original
gave it. [The port contract](port-contract.md) names those symbols (the
rows `from: link`), and `port-check` refuses an image whose script does not
define one of them.

### Adding a section

A part that adds a section says where it goes with the linker's own
`INSERT`, naming a section of the runtime's part:

```
/* one section of my own, after .rodata */
SECTIONS
{
  .user_table : { __user_table = .; KEEP(*(.user_table)) } > CODE
}
INSERT AFTER .rodata;
```

```sh
tools/bare-full/spinel-bare-full build --board an521 \
  --runtime RT/libspinel_rt_bare.a --link-add user.ld app.rb app.elf
```

This is how a chip family puts a boot block in front of the vector table
(`INSERT BEFORE .vectors`, as the tests' control family does in
[its part](../../tests/port-contract/fixtures/boards/chip/tchip/link.ld));
a user's section is placed by the same mechanism. The runtime's part has no holes kept open
for additions and needs none.
[`tests/port-contract/fixtures/user-part.ld`](../../tests/port-contract/fixtures/user-part.ld)
is a part the board lane adds to every board's build: it writes 16 bytes of
its own, so it needs no object.

Measured for `an521`: with 16 bytes in `.user_table`, the section sits
between `.rodata` and `.ARM.exidx`, the flash image grows by exactly 16
bytes (192,756 to 192,772 for a hello), and the only new symbols are the
section's own. With no object carrying the section and nothing written by
the script, the flash image does not change at all.

## What a program may rely on in the layout

- **The vector table is 16 words**, the first thing in `CODE` unless a part
  inserts a section before it: the initial stack pointer, the reset entry
  and the core's exceptions 2 to 15. The runtime's part stops the link if
  `.vectors` is any other size. A program that copies the table to RAM to
  install handlers copies 16 words.
- **`.data` and every `.data.*` section are stored in `CODE` and copied to
  RAM at reset.** A function a program puts in a `.data.*` section
  therefore runs from RAM, which is how code that must not run from flash
  (while the flash is being erased, say) is written.
- **`__image_end`** is the load address one past the last byte of the
  image: the first free byte of flash on a board that runs from flash.

The first is checked at every link. The second is a property of the
script's `.data` line and is not checked by a test here.

## The build is six steps

| Step | Reads | Writes, in `OUT.elf.d/` unless said |
|---|---|---|
| `values` | the board file, the chip family's `chip.yaml`, `--set` | `bf-board.h`, `found` (the board file and the family's directory this build uses) |
| `program` | `APP.rb`, Spinel, `runtime/` (the defines, stand-in headers and forced header), the C library's headers | `app.c`, `spinel.log`, `app.o`, `objects.program` |
| `platform` | `platform/common/*.c`, `chip/<family>/*.c`, `bf-board.h` | `plat-<name>.o`, `chip-<name>.o`, `objects.platform` |
| `objects` | the program a chip family names under `objects` in its `chip.yaml`, the board file, `bf-board.h` | what that program makes (the control family: `chip-head.o`, a 16-byte block that goes in front of the vector table), `objects.objects` |
| `link` | the three `objects.*` lists, the link parts, `bf-board.h`, the runtime archive, the builtins, the C library, `--heap-kb` | the preprocessed link parts, `link.log`; `OUT.elf`, `OUT.elf.map` |
| `image` | `OUT.elf`, the chip family's `image` | `OUT.elf.bin`; `OUT.elf.uf2` when the family declares it |

`build` runs all six in that order. `--steps LIST` runs only the named
ones, on what earlier runs left in the work directory:

```sh
tools/bare-full/spinel-bare-full build --board an521 \
  --runtime RT/libspinel_rt_bare.a --steps link,image app.rb app.elf
```

- A step that needs an earlier step's output and does not find it stops
  with exit 2 and names the step to run first. An unknown step name is
  exit 64.
- **The port directories of the first run are the later run's too.** A
  step that finds another board file or chip family than `found` records
  stops with exit 2: run `values` again, or give the same `--port-dir`.
- **A value given with `--set` reaches the build in the `values` step**, so
  name that step too: `--steps values,link,image --set policy.stack_bytes=16384`.
- **`--steps` is a way to run a step again, not a build system.** It trusts
  the work directory and does not notice that a source changed since the
  step that compiled it.

### The link order is written down

Each of the first three compiling steps writes a list, `objects.program`,
`objects.platform` and `objects.objects`: the objects it made, one path a
line, in link order. The `link` step takes its objects from those three files, in that order,
and from nowhere else. The order of objects is part of the image (moving
one function group moves every address after it), so it is in a file a
person can read.

To put one more object in the link, append its path to a list and run the
link again:

```sh
echo /path/to/extra.o >> app.elf.d/objects.program
tools/bare-full/spinel-bare-full build ... --steps link,image app.rb app.elf
```

### Overriding an input

| What | How |
|---|---|
| the board file, the chip family | `--port-dir DIR`, `BAREMETAL_PORT_PATH` |
| one board or policy value | `--set KEY=N` |
| a link part | `--link-chip`, `--link-runtime`, `--link-add` |
| the objects linked | an `objects.*` list |
| the runtime archive | `--runtime` |
| Spinel, the C library, the builtins | `SPINEL_DIR`, `BAREMETAL_PICOLIBC`, `BAREMETAL_BUILTINS` |

A changed value shows where it should and nowhere else. Measured for
each board the board lane builds: halving `policy.stack_bytes` changes one
byte of the flash image (the heap's end, which the C library holds) and two
symbols.

## What a chip family may declare

Two optional keys of a family's `chip.yaml`, beside those
[the board file's guide](board-file.md) lists:

```yaml
objects: boot/object.rb
image:
  flash_origin: chip.flash.origin
  flash_bytes: chip.flash.size_bytes
  uf2: { family_id: 0x12345678 }
```

(The example is the tests' control family,
[`tests/port-contract/fixtures/boards/chip/tchip`](../../tests/port-contract/fixtures/boards/chip/tchip).)

- **`objects`** names a program in the family's directory that makes
  objects only that family needs. The driver runs it in the `objects` step
  with the board file, the generated header, the work directory and the
  compiler's command line, and links the `chip-*.o` files it prints on its standard
  output, after the platform's. This is where a chip whose boot ROM wants
  a block in front of the image makes it: a second-stage boot chosen by a
  board value, padded and given the checksum the ROM checks. The control
  family's program makes a 16-byte block that begins with a board value.
  The driver itself knows nothing of any chip's boot scheme.
- **`image.flash_origin` and `image.flash_bytes`** say where the flash is
  that an image is written to. Each is a key path naming a value the two
  files already state (here the family's flash origin and flash size; a
  family whose boards differ in flash size names `board.<path>` for the size), so the range is written once; a plain integer is accepted too. The key paths are spelled as
  `board-check --values` prints them (`chip.<path>`, `board.<path>`,
  `policy.<key>`). With them, the `image` step first checks every loaded segment of
  the ELF: one outside the range stops the step with exit 1 before any format is
  written, and a `.bin` or `.uf2` left by an earlier run is removed:

  ```
  a loaded segment at 0x20000000 (1420 bytes) is outside the flash, 0x10000000 to 0x10100000; nothing was written
  ```

  Without the check, a link that put something in RAM's address range by
  mistake would give a flat file hundreds of megabytes long and say
  nothing. Every family here states its range; a family that states
  none is not checked.
- **`image.uf2`** makes the `image` step write `OUT.elf.uf2` as well, with
  that family id: 512-byte blocks of 256 payload bytes, every loadable
  segment at its load address, gaps inside a page filled with zeros.

A boot block and its checksum are made **before** the link, because the
block is part of the image. Nothing is done to an image after it is
linked except to write it in another format.

## Limits

- **lld only.** The parts are joined in the way the pinned LLVM's linker
  was measured to accept: several scripts, `INSERT` applied even when its
  script comes before the one that defines the section it names, `MEMORY`
  first. GNU ld was not tried.
- **A replaced part is yours.** The driver checks nothing in it. The link's
  own errors and `port-check` are what hold it.
- **`.data.*` in RAM is stated, not tested.** No lane builds a function
  into a `.data.*` section and checks its address.
- **The `objects` program is run with the Ruby that runs the driver.**
- **One step is not checked against its inputs' dates** (above).
