# spinel-modular

Checked routes for compiling Ruby ahead of time with
[Spinel](https://github.com/matz/spinel): three that compile a part of a
program you declare into native code that needs no garbage collector and no
language runtime, and one that puts a whole program, runtime and collector
included, on a microcontroller with no operating system.

Spinel compiles a whole program with its runtime and collector: this is
`full`. spinel-modular adds the tools with which you declare that a method
stands without the runtime, and which check that claim and package the
result. Nothing chooses for you which methods those are.

1. **You declare the boundary; the compiler checks it.** The method's whole
   call closure must allocate nothing and call nothing in the runtime.
2. **What cannot be verified is refused**, with a diagnostic. It is not
   compiled through the hosted runtime instead. That holds for a construct
   outside a route's subset, a type the compiler has no evidence for, an
   unresolved call, a platform call the target profile does not list, an
   undefined symbol, and a contract, profile or board file its checker
   cannot accept.
3. **A source check is not the end.** The generated object is checked again
   at its boundary: which symbols it exports and which it leaves undefined.
   Admission of the source alone is not treated as proof that an object is
   independent of the runtime.

The three runtime-independent routes share that goal and nothing else. Each
has its own declaration, its own ABI and its own packaging:

| You write | Route | Tool |
|---|---|---|
| ordinary Ruby, and name a method with `--core` | native core | `tools/core/spinel-core-build` |
| Ruby and a contract file (`.contract`) | CORE boundary | `spinel-core-kernel` |
| Ruby with `freestanding_def`, and a target profile | freestanding kernel | `spinel-fs-emit` |

Freestanding is not a target option of `--core`, and the CORE boundary is not
a mode of the native-core driver. The fourth route, full on bare metal, is of
another kind: it keeps the runtime and the collector.

A runtime-independent boundary is a claim that is checked, not a hint. A
method that merely happens not to trigger the collector does not qualify.

## What it does

| Route | What you get | Start here |
|---|---|---|
| **Native core** | An ordinary Ruby method, selected with `--core`, compiled to a native object and linked into the hosted executable in place of the runtime's version of the method. The rest of the program still runs on the hosted runtime; what is independent is the core object. The driver checks the method's source closure, then checks the object it emitted: its exports in the core namespace must be exactly the mapped symbol, that symbol must have code, and it may leave nothing undefined but the one failure hook the driver names, through which a failed arithmetic check ends the program. This route admits a small subset of integer code. Arithmetic is checked: overflow and division by zero end the program as the Ruby exception would. | [Building a native core executable](docs/native-core/reproducing.md), [what is implemented and what is refused](docs/native-core/supported-envelope.md) |
| **CORE boundary** | A method with a written contract (integer scalars and lent buffers, their widths and mutability) compiled to a C-callable object and header. A failure comes back as a status (`ARGUMENT`, `ARITHMETIC`, `BOUNDS`, `CAPACITY`), never as a trap. The hosted side owns the storage and lends buffers through a generated adapter. | [The buffer boundary](docs/core/buffer-boundary.md) |
| **Freestanding kernels** | Methods declared with `freestanding_def`, compiled for a target profile: Cortex-M33 and RV32 under Zephyr, wasm32, and, as a separate lane, a bare Cortex-M33 with no RTOS. Each profile states its ABI, integer width and the platform calls it allows; an object that leaves any other symbol undefined is refused. A boundary value that does not fit its declared width, or an overflow unless the declaration says to wrap, is a trap. | [Declaring a core boundary](tools/freestanding/README.md), [target lanes](tests/freestanding/README.md) |
| **Full on bare metal** | A whole Ruby program, with the runtime and its collector, linked into one image for a Cortex-M33 or a Cortex-M0+ with no operating system. This is not a runtime-independent route: the image holds the runtime. QEMU's `mps2-an521` and the FRDM-MCXN947 are the boards kept here, both Cortex-M33; the Cortex-M0+ path is built and held to the contract with a control fixture, and no Cortex-M0+ board is kept or run here. A board is a file of values, not code, and a board or a chip family of your own is kept in a directory of your own, outside this repository, and named to the build. The symbols that cross between the program, the runtime, the C library, the start-up code, the chip's code and the link script are named in a contract, and a checker reads the linked image, not only the configuration, and refuses a build that crosses one the contract does not name. | [tools/bare-full](tools/bare-full/README.md), [the port contract](docs/platform/port-contract.md), [the board file](docs/platform/board-file.md) |

What each route records about a build differs too:

- **CORE boundary:** `spinel-core-kernel` can write a versioned
  [core report](docs/core/core-report.md) for an entry. The loop bound
  (with the work bound) and the stack budget are evaluated today; the
  other four properties appear in every report marked as not evaluated.
- **Freestanding:** the emitter can write a ledger of the symbols the object
  leaves undefined (`--emit-undef-tsv`), which its gate holds to the
  profile. It does not write the core report.
- **Native core:** no report. The driver writes and checks a ledger of the
  source files the compiler read.
- **Full on bare metal:** a build the port contract's checker accepts gets
  a report of which of the contract's names it used.

## Quick start

On Debian x86_64 with LLVM 23.1.1 (with MLIR) at `/opt/llvm-23.1.1`:

```sh
export LLVM_PREFIX=/opt/llvm-23.1.1
export CLANG="$LLVM_PREFIX/bin/clang" CC="$LLVM_PREFIX/bin/clang" NM="$LLVM_PREFIX/bin/llvm-nm"
git submodule update --init --recursive
make -C vendor/spinel deps CC="$CC"
make -C vendor/spinel -j8 CC="$CC"
tools/contract/build.sh
tools/mlir/native/build.sh

mkdir -p build
tools/core/spinel-core-build --source tests/native-core/fixtures/lower.rb \
  --core lower -o build/lower.bin
./build/lower.bin
```

This exercises the native-core route.
[Building and testing](docs/building.md) lists the requirements of every
route and the command of every test suite. A comparison with another
implementation, CRuby for one, is classed as an oracle: such sections are
listed in `tests/ORACLES.tsv` and run only with `ALLOW_ORACLE=1`.

## Limits

- **Native core** admits a small subset: integer literals, comparisons,
  conditionals, local variables, checked integer arithmetic, bitwise
  operators and shifts, the listed intrinsics, and direct calls to helpers
  resolved statically. Float and String arguments, loops, buffers and
  unresolved calls are refused, and the top level may only define methods
  and call into the selected closure with integer literals
  ([what is implemented and what is refused](docs/native-core/supported-envelope.md)).
- **CORE boundary** admits more, under its contract: integer scalars and
  lent buffers of integer elements, `while` loops and loops with a literal
  block (`times`, `upto`, `downto`, `each` over a declared buffer), helper
  calls and early `return`. It has no Float. Every failure is a status. The
  [construct table](tests/core-boundary/fixtures/constructs/constructs.tsv)
  says exactly what is admitted.
- **Freestanding** has integers of the target's width, Float values and
  buffers where its lanes exercise them, `while` loops and loops with a
  literal block, and
  only the platform calls its profile lists
  ([declaring a core boundary](tools/freestanding/README.md)).
- **None of the three is a whole program.** The hosted side, or your C
  code, owns storage, I/O and anything that allocates.
- **Integer width is a route's own rule.** A native-core method computes in
  64 bits. A CORE-boundary body computes in 64 bits by default, and the
  contract gives each boundary value its own width. A freestanding body has
  the target's pointer width: 64 bits on a 64-bit host, 32 on Cortex-M33,
  RV32 and wasm32, where a 64-bit declaration is refused unless a table
  lists the source. A whole program on bare metal has a 32-bit Integer.
- **Full on bare metal** has no files, processes, signals, threads or
  `Fiber`, and some calls that face an operating system exist only to fail
  with `ENOSYS`. It is measured with the programs of its own suite
  ([tools/bare-full](tools/bare-full/README.md) has the limits).
- **Boards.** No default suite runs on hardware. The FRDM-MCXN947's runs of
  the bare-metal build, made by hand, are recorded in
  [runs on boards](docs/platform/board-runs.md). The Cortex-M0+ path
  of the bare-metal build has not run on hardware from this repository.
- **Hosts.** The checks in this repository have been run on Debian 13
  x86_64. The sources also support macOS arm64 with the official LLVM
  release
  ([installation record](docs/toolchains/llvm-23.1.1-macos/INSTALLATION-RECORD.md)).

## Layout

| Path | Contents |
|---|---|
| `vendor/spinel` | the pinned Spinel compiler (a git submodule) |
| `tools/contract` | the reader that takes type and call facts from Spinel |
| `tools/mlir/native` | the source and contract checkers, the MLIR lowering, code generation for the CORE boundary and for freestanding kernels, the core report and the packaging tools |
| `tools/core` | the native-core driver, the artifact gate and helpers for the hosted side |
| `tools/bare-full` | the build of a whole `full` program for a Cortex-M with no operating system: the driver, the start-up and OS-call code, chip family code and board files |
| `tools/freestanding`, `tools/platform` | the declaration surface, target profiles and platform ledger; the port contract of a bare-metal build and its checker |
| `tests` | the acceptance suites, one directory a subject |
| `docs` | guides and toolchain records |

## Relation to Spinel

spinel-modular is a separate project and does not imply endorsement by
Spinel's authors. It builds against a pinned revision of a Spinel fork that
carries a small set of patches; [provenance](docs/provenance.md) names the
revision and the other code here that comes from elsewhere.

## License

spinel-modular is licensed under the Apache License 2.0 with LLVM Exceptions
(`Apache-2.0 WITH LLVM-exception`); see [LICENSE](LICENSE) and
[NOTICE](NOTICE). The exceptions matter for a compiler: code of this project
that compiling embeds in your program needs no attribution there. Files that
keep another licence are listed in [THIRD_PARTY.md](THIRD_PARTY.md).
