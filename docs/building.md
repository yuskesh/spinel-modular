# Building and testing

## Requirements

| What | Version | Needed for |
|---|---|---|
| LLVM with MLIR | 23.1.1, the official release, selected through `LLVM_PREFIX` | everything |
| A C compiler | the release's own `clang` (`CC`) | everything |
| Git, GNU Make, curl, tar, CMake, Ninja | any recent | building Spinel and the tools |
| Ruby | 3.3 or later (it ships Prism) | the test suites and the reports' tools |
| Zephyr and its SDK | v4.4.2 and SDK 1.0.1, with `west` on PATH | the Cortex-M33 and RV32 lanes |
| QEMU | `qemu-system-arm` with `mps2-an521`; the Zephyr SDK's QEMU for RV32 | running the device lanes, the CORE boundary's 32-bit intrinsics lane and the bare-metal suite |
| wasi-sdk | a wasm32 sysroot and `libclang_rt.builtins.a` | the wasm32 lanes |
| node and wrangler | on PATH; node 24 and wrangler 4.61.1 were used | running the wasm32 lanes |
| compiler-rt builtins for ARMv8-M | built from LLVM 23.1.1 | the bare Cortex-M33 lane; the CORE boundary's 32-bit intrinsics lane; a full-tier bare-metal build for Cortex-M33 |
| compiler-rt builtins for ARMv6-M | built from LLVM 23.1.1 | a full-tier bare-metal build for Cortex-M0+: the control board of `tests/port-contract/boards.sh`, and a Cortex-M0+ board of your own |
| picolibc | 1.8.12, built with LLVM 23.1.1, once for Cortex-M33 and once for Cortex-M0+ | a full-tier bare-metal build (`tools/bare-full`) |

The first four rows are enough for the native core route and the CORE
boundary. The rest is for the freestanding targets.

On Debian, the measured LLVM prefix is `/opt/llvm-23.1.1`. On macOS arm64,
build only with the official LLVM 23.1.1 release, never Apple Clang; the
[installation record](toolchains/llvm-23.1.1-macos/INSTALLATION-RECORD.md)
has the steps. The records for
[Zephyr](toolchains/zephyr-v4.4.2/INSTALLATION-RECORD.md) and
[compiler-rt](toolchains/compiler-rt-23.1.1/INSTALLATION-RECORD.md) and
[picolibc](toolchains/picolibc-1.8.12/INSTALLATION-RECORD.md) say how
each installation used here was made, for each core.

On Debian 13 the release's `lld` needs ICU 70 at run time; put its library
directory in `LD_LIBRARY_PATH`.

## Build

From the repository root:

```sh
export LLVM_PREFIX=/opt/llvm-23.1.1     # on macOS, your prefix, for example $HOME/.local/opt/llvm-23.1.1
export CLANG="$LLVM_PREFIX/bin/clang" CC="$LLVM_PREFIX/bin/clang" NM="$LLVM_PREFIX/bin/llvm-nm"
git submodule update --init --recursive
make -C vendor/spinel deps CC="$CC"     # downloads Spinel's dependencies
make -C vendor/spinel -j8 CC="$CC"      # the pinned Spinel compiler and runtime
tools/contract/build.sh                 # spinel-typedump, the fact reader
tools/mlir/native/build.sh              # the checker, the kernels and the packaging tools
```

`tools/mlir/native/build.sh` builds ten tools into
`tools/mlir/native/build/bin`: `spinel-core-check`, `spinel-core-emit`,
`spinel-core-boundary`, `spinel-core-kernel`, `spinel-core-stack`,
`spinel-core-adapter`, `spinel-core-package`, `spinel-fs-check`,
`spinel-fs-emit` and `spinel-fs-codegen`.

Each build records a stamp of the sources it was made from. A test suite
refuses a tool whose stamp does not match the tree, and says which inputs
differ: rebuild after changing a source or moving `vendor/spinel`. The stamp
reads the tree through git, so build from a checkout, not from an unpacked
archive.

## Using it

- A native core executable: [reproducing guide](native-core/reproducing.md).
- A C-callable object from a contract: [the buffer boundary](core/buffer-boundary.md).
- A kernel for a device or wasm32: [tools/freestanding](../tools/freestanding/README.md).
- A whole program, with the runtime and its collector, for a Cortex-M with
  no operating system: [tools/bare-full](../tools/bare-full/README.md). The
  agreement between its parts is [the port contract](platform/port-contract.md),
  and a board is [a file of values](platform/board-file.md).
- Checking a method without building it:

  ```sh
  tools/mlir/native/build/bin/spinel-core-check app.rb --method pick
  ```

  See [core source eligibility](../tools/core/README.md).

## Tests

Every suite is one command, run from the repository root with the variables
above exported. A suite prints a summary line with its counts (some print a
note after it) and exits non-zero on a failure; a suite that cannot run on
the host, or lacks a tool it needs, says SKIP and exits 2. `DIR` is an empty scratch directory of your choice, outside the
checkout.

| Subject | Command |
|---|---|
| Core source eligibility | `ruby tests/core-eligibility/run.rb`, `sh tests/core-eligibility/upstream-fields.sh` |
| The standalone core object route (x86_64 Linux only; skipped elsewhere) | `SPINEL_CORE_BUILD=tools/mlir/native/build sh tests/core/run.sh` |
| Native core executables | `sh tests/native-core/run.sh`, and `driver.sh`, `ledger.sh` and `arith.sh` in the same directory |
| Native core objects on macOS arm64 (Mach-O) | `ruby tests/native-core/macos-probe.rb` |
| The CORE boundary | `sh tests/core-boundary/run.sh`; its lanes alone, for example `sh tests/core-boundary/intrinsics.sh` and `sh tests/core-boundary/intrinsics-32.sh` |
| Bit and word operators | `sh tests/core-bitwise/run.sh` |
| Blocks and bounded loops | `sh tests/core-blocks/run.sh` |
| Stack measurement | `sh tests/core-stack/run.sh` |
| The core report | `sh tests/core-report/run.sh` |
| The checked subset's tables | `sh tests/subset/map.sh DIR`, `sh tests/subset/reasons.sh DIR`, `sh tests/subset-tables/run.sh` |
| Lowering inputs | `sh tests/lowering/locations.sh DIR`, and `reopened.sh`, `split.sh` and `duplicate.sh` the same way |
| The fact reader | `sh tests/contract/rewrites.sh`, `ruby tests/contract/int-width.rb` |
| Freestanding targets | `sh tests/freestanding/run.sh`, `sh tests/freestanding/stamp-controls.sh DIR` |
| Buffers lent to helpers | `sh tests/fs-helper-buffers/run.sh` |
| Source stamps | `sh tests/source-stamp/run.sh` |
| A full-tier program on a bare Cortex-M33 (QEMU) | `sh tests/bare-full/run.sh` |
| The port contract | `sh tests/port-contract/run.sh`, `sh tests/port-contract/board.sh`, `sh tests/port-contract/boards.sh DIR` |
| The oracle gate | `sh tests/oracle/check.sh`, `sh tests/oracle/run.sh` |

The freestanding suite needs the target toolchains; its
[README](../tests/freestanding/README.md) lists the variables. Its board
lanes are not run without a board (`FRDM_HOST`), and say so.

`tests/core-boundary/run.sh` runs the CORE boundary's lanes. One of them,
`intrinsics-32` (`tests/core-boundary/intrinsics-32.sh`), builds the 32-bit
cases of the word intrinsics for a Cortex-M33 and runs them under QEMU's
`mps2-an521` with no RTOS and no C library: a 32-bit body needs a 32-bit
target. It needs `qemu-system-arm` (`QEMU_ARM`, or on PATH) and
`BAREMETAL_BUILTINS` for ARMv8-M; without them the suite reports that lane as
not run.

`tests/bare-full/run.sh` builds whole programs with
`tools/bare-full/spinel-bare-full` for a Cortex-M33 and runs them under
QEMU's `mps2-an521`. It needs `BAREMETAL_PICOLIBC` and `BAREMETAL_BUILTINS`
for that core, `qemu-system-arm`, and a built `vendor/spinel`.

`tests/port-contract/boards.sh` builds every board that has a board file
under `tools/bare-full/board`, in a directory of `BAREMETAL_PORT_PATH`, or
among its own fixtures (one control board, for a Cortex-M0+), and holds each
build to the port contract. It
needs a built `vendor/spinel` (or `SPINEL_DIR` naming one) and the
bare-metal C library and builtins of each core; the script's header lists
the variables. Without a built Spinel, or for a core whose variables are
missing, it prints `NOT RUN` and the rest is unaffected. No suite runs an image on a
board.

### Comparisons with another implementation

Some suites hold a section that compares an answer with another
implementation's, CRuby's for example. Those sections are listed in
`tests/ORACLES.tsv` and run only with `ALLOW_ORACLE=1`; without it they print
`NOT RUN (oracle)` and the rest of the suite runs. The routine checks are the
compiler's own refusals and each suite's recorded answers.
