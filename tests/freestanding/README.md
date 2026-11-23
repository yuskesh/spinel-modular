# Freestanding kernels on targets

These lanes build `freestanding_def` kernels for targets other than the host and
run them: QEMU Cortex-M33 (`mps2/an521`), QEMU RISC-V 32 (`qemu_riscv32`), and
wasm32 under node and workerd. The kernel's object is written by
`spinel-fs-emit` through `spinel-fs-codegen`, for the profile each lane names
([tools/freestanding](../../tools/freestanding/README.md)). `bare` runs the
first lane's kernel on the same Cortex-M33 machine with no RTOS, so that what
`kern.o` needs is visible in the final image.

Each lane is named after what it tests: integer boundaries, the wasm32
target, buffers, platform externs, and bare metal.

## What runs where

| Lane | Capability | Cortex-M33 | RV32 | wasm32 |
|---|---|---|---|---|
| `ints` | the first kernel: integer boundaries, traps, the panic platform | QEMU; FRDM-MCXN947 board (`run_frdm.sh`) | QEMU | - |
| `wasm` | the wasm32 profile, with the `ints` kernel unchanged | - | - | node, workerd |
| `buffers` | Float values and pointer+length buffers across the boundary | QEMU | QEMU | node |
| `externs` | platform externs declared by the profile (uptime, sleep, print, GPIO) | QEMU | QEMU | node |
| `bare` | the `ints` kernel with no RTOS: the lane's own startup, UART console and setjmp, and compiler-rt's builtins | QEMU, no Zephyr | - | - |
| `bare-frdm` | `bare` on the MCX N947: its own startup, memory map and LPUART console, bare's driver, setjmp and builtins | FRDM-MCXN947 board, no Zephyr or SDK | - | - |
| `profiles` | every shipped profile is read; each platform-first one emits | object | object | object |

The checks the lanes run are the compiler's own refusals and accept/reject
tests, plus properties of the runs themselves:

- emission for each target, through the emitter's undefined-symbol gate;
- `.mlir` determinism;
- the ABI table (`spinel-fs-check --abi`);
- the export map;
- the undef-gate and extern-check control tables;
- the reject tables and their controls;
- on each target, every case running to its `END` marker without a `FATAL` line;
- the trap probes, and the panic image stopping at the trap;
- the device property rows (uptime, sleep, GPIO, print);
- the wasm import shape;
- the strict link without builtins being refused;
- the workerd results agreeing with node's for the same module;
- in `bare`: the trap code of each
  of the `ints` kernel's seven trapping cases, no undefined symbol in either image, and that
  the images hold nothing but the driver, `kern.o` and members of the builtins
  archive, checked by input and by symbol, with a control image each check has
  to refuse; and that its rows and its `kern.o` equal `ints`'s Zephyr run of
  the same kernel (one compiler, two platforms of this repository);
- in `ints/run_frdm.sh`: the same `kern.o`, linked by Zephyr
  for `frdm_mcxn947/mcxn947/cpu0` and run on the board, runs every case to
  `END`, the panic image stops at its trap, and both consoles equal the QEMU
  run's line for line, `BEGIN` aside; each image arrives on the host intact,
  is written, and is the one that printed (its `BEGIN` names the board);
- in `bare-frdm`: bare's checks on the board -- every
  case to `END`, the seven trap codes, the panic image stopping at its trap,
  no undefined symbol, and nothing in either image but the driver, `kern.o`
  and builtins members, each with its control -- with the panic core's halted
  PC on the trap hook's final self-branch where bare asks QEMU whether it is
  still running; `kern.o` byte-identical to bare's and every row equal to
  bare's QEMU run; and the build refusing a driver that is not bare's.

## Running

```sh
export LLVM_PREFIX=/path/to/llvm-23.1.1
export ZEPHYR_BASE=/path/to/zephyr-v4.4.2/zephyr
export ZEPHYR_SDK_INSTALL_DIR=/path/to/zephyr-sdk-1.0.1
export WASI_BUILTINS=/path/to/wasm32-unknown-wasip1/libclang_rt.builtins.a
export WASI_SYSROOT=/path/to/wasi-sysroot
export BAREMETAL_BUILTINS=/path/to/libclang_rt.builtins-armv8m.main.a  # docs/toolchains/compiler-rt-23.1.1
export QEMU_ARM=/path/to/qemu-system-arm  # bare; default: on PATH, with mps2-an521
# optional: FRDM_HOST and the rest for the FRDM-MCXN947 board (see below)
# west (from the Zephyr venv), node and wrangler on PATH
tools/contract/build.sh                   # spinel-typedump
tools/mlir/native/build.sh
sh tests/freestanding/run.sh
```

A lane that needs one of them and finds it missing names it and exits 2.

Each lane can also run on its own, in the order `run.sh` uses. For example,
`bash tests/freestanding/externs/build_all.sh`, then `run_extern_check.sh`,
`run_gates.sh` and `run_reject.sh`. Output goes under `$FS_WORK`, which defaults
to `$TMPDIR/spinel-freestanding`. Nothing is written into the source tree.
Each lane writes under `$FS_WORK/<lane>` and takes no other location from the
environment; in particular an exported `OUT` or `W` is ignored. The scripts that
start from an empty directory (`build_all.sh`, `wasm/build.sh`, and the
`reject`, `rej` and `host` directories under the lane) remove it only if
`tests/freestanding/workdir.sh` created it, which leaves a
`.spinel-freestanding-workdir` marker inside, and otherwise stop with exit 2. A
lane directory left by a run before this check has no marker; remove it once.

`ZEPHYR_SDK_INSTALL_DIR` is only a hint to Zephyr's CMake, which falls back to
its own search when the value is wrong. So every `west build` prints the
toolchain Zephyr actually found. Compare that line with the path you meant.

The lanes need these tools, at these versions:

- the official LLVM 23.1.1, which includes `wasm-ld`. On Debian 13 its `lld`
  needs ICU 70 (`libicu*.so.70`), which Debian 13 does not ship; put those
  libraries on `LD_LIBRARY_PATH`;
- Zephyr v4.4.2 with SDK 1.0.1, whose own QEMU (`qemu-system-arm` and
  `qemu-system-riscv32`, 10.0.2) the `run` targets use;
- wasm32 builtins for `WASI_BUILTINS` and a WASI sysroot for `WASI_SYSROOT`:
  wasi-sdk 34 (`libclang_rt-34.0`, whose
  `wasm32-unknown-wasip1/libclang_rt.builtins.a` is the builtins, and
  `wasi-sysroot-34.0`), or a packaged `wasi-runtimes` and `wasi-libc`;
- node 24 and wrangler 4.61.1, which brings workerd;
- for `bare`, compiler-rt 23.1.1's `libclang_rt.builtins-armv8m.main.a`, built
  from the release sources (docs/toolchains/compiler-rt-23.1.1), and a
  `qemu-system-arm` (10.0) with the mps2-an521 machine as `QEMU_ARM`.

The LLVM release ships no wasm32 builtins. The kernels need `__multi3` from
them, and `wasm` checks that a link without them is refused.

### The FRDM-MCXN947 board

Two lanes run on the board: `ints/run_frdm.sh`, after `ints`'s `build_all.sh`
and `run_gates.sh`, and `bare-frdm`, after `bare`. They need hardware, so
they are the lanes that can be **NOT RUN**: without a prerequisite they say
which is missing and exit 3, and `run.sh` prints the reason and goes on.
`bare-frdm`'s image checks need no board, so they run and are counted
either way. With `REQUIRE_ALL=1` a lane that could not run is a failure, in
the scripts and in `run.sh`. Both drive the board's host through
`tests/freestanding/frdm-host.sh`.

```sh
export FRDM_HOST=user@host          # ssh destination; unset, the lane is NOT RUN
export FRDM_LINKSERVER=/path/to/LinkServer  # on that host; default /usr/local/LinkServer/LinkServer
export FRDM_TTY=/dev/ttyACM0        # the MCU-Link VCOM on that host (the default)
# FRDM_PROBE ('#1') and FRDM_TIMEOUT (60 s per console) are optional
sh tests/freestanding/ints/run_frdm.sh
bash tests/freestanding/bare-frdm/build_all.sh   # after bare
bash tests/freestanding/bare-frdm/run_gates.sh
bash tests/freestanding/bare-frdm/run_join.sh
```

What it needs:

- **a Linux host with NXP LinkServer**, which the board's MCU-Link (J17) is
  plugged into with a data cable, and which accepts `ssh` with a key and no
  prompt (`BatchMode`). The console is read there with GNU `stty` and
  `timeout`. Verified with LinkServer 26.3.123 for Linux aarch64 and the
  MCU-Link's CMSIS-DAP firmware 3.172. A charge-only USB cable leaves the host
  seeing nothing, which reads as no probe.
- **not macOS arm64 as that host.** There LinkServer 26.6.137 and 26.9.130
  (macOS 27.0.1) list the MCU-Link and then fail every command with
  `Error: Probe not open`; `west flash -r linkserver` ends in `Flash operation
  exited with code 1`. The lane checks that LinkServer's probe list names the
  device and board, which an unopened probe leaves blank, and reports such a
  host as NOT RUN.
- the board out of ISP mode, and nothing else using the probe.

The images are built on this machine and copied to the host; the
host's files go in one `mktemp -d` directory per run, removed when the run
ends. LinkServer resets the target before it writes, so the image already in
flash boots once; the console is therefore opened after the write, and a reset
on the probe's wire (`probe wiretimedreset`) starts the new image. The run
LinkServer starts after the write can still be printing then, so the wait for
a console's terminator, and the checks, read it from its last `BEGIN` on. For
`ints` the board's Zephyr configuration
leaves `CONFIG_FPU` unset, so its objects use the soft-float ABI, as the
`cortex-m33-zephyr` profile's `kern.o` does; only DSP differs (`+nodsp`), and
the link reports nothing.

`bare-frdm` takes nothing from Zephyr or NXP's SDK into the image. Its
`src/` holds what is the chip's, each value with its source in a comment:

- **memory**: code at 0x10000000, the 2 MB flash in CPU0's secure alias, and
  RAM in RAMA, the first 32 KB block of SRAM at 0x30000000 (Zephyr's DTS);
- **startup**: the boot ROM takes the initial SP and reset vector from the
  start of flash. The entry masks interrupts, clears MSPLIM, sets MSP and
  points VTOR at its own table before any C runs, because what the ROM leaves
  in them is not documented here. Words 0x20-0x2b of the table are ARMv8-M
  reserved and stay zero, as in Zephyr's image for the board: written by
  LinkServer, an image in that shape boots from a pin reset, with nothing in
  the image-length or image-type words. A power-on boot was not tried;
- **console**: LP_FLEXCOMM4 as an LPUART on P1_8/P1_9, which the board wires
  to the MCU-Link VCOM (UM12018), clocked from FRO_12M through SYSCON, with
  the registers of NXP's device headers as Zephyr's `hal_nxp` ships them;
  115200 baud is OSR 26, SBR 4 (+0.16%).

The driver half of `src/main.c` is bare's, with only the `BEGIN` line's
platform name changed, and `build_all.sh` stops if it is not. The PC is read
with LinkServer's script language (`probe runscript`: connect, halt, read
r15), which leaves the core halted.

## No comparison with a host build

The lanes check that each target ran every case to its end, that the traps
stop and that the refusals refuse. They do not compare a target's values
with a host build of the same Ruby through Spinel's C back end: that would
be a check against another implementation, and this repository has no
runner for it. The host driver `ints/mkcases.rb --host` writes is there for
such a comparison made by hand.

In place of those joins, each lane checks that every case ran. That is a
count of printed rows per target, and it says nothing about the values.

## Rows printed as NOT-AVAILABLE

- **`ints` undef rows e05-e07.** They need a host-mode object from a hosted
  MLIR importer this repository does not have.
- **`buffers` control e11.** It uses a typing path (`--types-from emit-types`) the
  native emitter does not have; it accepts only `contract`.

## Known wording defects

One refusal is right about the kernel and vague about the reason:

- `externs` k6 is refused as `unsupported: 'gpio_set'`, which does not say that
  the name collides with a top-level method.

QEMU is stopped at the console's terminator in every lane. The wasm import
list is read with node, because the LLVM release ships no `obj2yaml`.
