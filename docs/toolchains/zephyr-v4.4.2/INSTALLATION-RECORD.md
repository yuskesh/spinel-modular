# Zephyr v4.4.2 installation record

The Cortex-M33 and RV32 lanes of `tests/freestanding` build with this
installation. It lives outside the repository, and nothing in the repository
depends on its path: the lanes read `ZEPHYR_BASE` and
`ZEPHYR_SDK_INSTALL_DIR` and refuse to run without them.

## The release

- Release: **Zephyr v4.4.2**, tag object `671f64aa79924606253238f801c494c84b02c2a0`,
  commit `dccb09599635bdff17633fa7e9dab014b91dce90` ("release: Zephyr 4.4.2",
  2026-08-06). Both from `git ls-remote --tags https://github.com/zephyrproject-rtos/zephyr 'v4.4.2*'`
  (the `^{}` row is the commit).
- It has `mps2/an521/cpu0` and `qemu_riscv32` under QEMU and
  `frdm_mcxn947/mcxn947/cpu0`, and its `SDK_VERSION` file says `1.0.1`.
- SDK: **Zephyr SDK 1.0.1** (`sdk_version` file), `arm-zephyr-eabi-gcc (Zephyr SDK 1.0.1) 14.3.0`,
  GNU ld 2.43.1, for Debian x86_64 and macOS arm64. Its host tools supply
  the `dtc` (1.7.0) and the QEMU the build uses (below).
- west manifest: `zephyr/west.yml` at that commit, with the project filter
  `-.*,+cmsis,+cmsis_6,+hal_nxp,+picolibc`. `west list` after `west update`:

  | project | path | revision |
  |---|---|---|
  | zephyr (manifest) | `zephyr` | `dccb09599635bdff17633fa7e9dab014b91dce90` |
  | cmsis | `modules/hal/cmsis` | `512cc7e895e8491696b61f7ba8066b4a182569b8` |
  | cmsis_6 | `modules/hal/cmsis_6` | `30a859f44ef8ab4dc8f84b03ed586fd16ccf9d74` |
  | hal_nxp | `modules/hal/nxp` | `7554bc0f6f6c284972eba7b2c17b16fbb9cc0ad0` |
  | picolibc | `modules/lib/picolibc` | `01254932e8e81085817ed61fd858648584ffe37c` |

  The filter keeps the workspace at 2.6 GB with shallow clones.

## Python, inside the installation only

- `python3 -m venv "$ROOT/.venv"`, Python 3.13.
- `west==1.5.0` pinned by pip.
- `zephyr/scripts/requirements-base.txt` at the pinned commit, sha256
  `ceff4012613375d167ccd085ef19875c79045359f006f678ff9f4df3c4aa7206`.
- The venv is put first on `PATH` in the same command that runs `west`.
  Python runs only through `west` and Zephyr's CMake; no Python file is part
  of this repository.

## Install commands

```sh
ROOT=$HOME/toolchains/zephyr-v4.4.2; TAG=v4.4.2
mkdir -p "$ROOT" && cd "$ROOT"
python3 -m venv "$ROOT/.venv"
export PATH="$ROOT/.venv/bin:$PATH"
python3 -m pip install --quiet --upgrade pip
python3 -m pip install --quiet west==1.5.0
west init -m https://github.com/zephyrproject-rtos/zephyr --mr "$TAG" "$ROOT/workspace"
cd "$ROOT/workspace"
west config manifest.project-filter -- '-.*,+cmsis,+cmsis_6,+hal_nxp,+picolibc'
west update --narrow -o=--depth=1
python3 -m pip install --quiet -r "$ROOT/workspace/zephyr/scripts/requirements-base.txt"
git -C zephyr rev-parse HEAD                 # dccb09599635bdff17633fa7e9dab014b91dce90
git -C zephyr describe --tags --exact-match  # v4.4.2
cat zephyr/SDK_VERSION                       # 1.0.1
```

About 100 s on Debian, most of it the clone. On macOS, create the venv with
the Python you mean by absolute path if `python3` on `PATH` belongs to
another environment; every later command is the same.

`west zephyr-export` is not run, and nothing is written to
`~/.cmake/packages`: that registry is shared with any other Zephyr project
on the machine.

## Paths

| variable | value |
|---|---|
| `ZEPHYR_BASE` | `$HOME/toolchains/zephyr-v4.4.2/workspace/zephyr` |
| `ZEPHYR_SDK_INSTALL_DIR` | `$HOME/zephyr-sdk-1.0.1` |
| `PATH` | `$HOME/toolchains/zephyr-v4.4.2/.venv/bin` first, for `west` |

## `ZEPHYR_SDK_INSTALL_DIR` is not authoritative; the CMake log is

Zephyr's `cmake/modules/FindZephyr-sdk.cmake` passes
`ZEPHYR_SDK_INSTALL_DIR` to `find_package` as `HINTS`, which excludes
nothing: when the path names no SDK, CMake continues with its default search
and can find another SDK on the machine. The configure then succeeds and
says nothing. Measured with a `--cmake-only` configure of `hello_world` for
`mps2/an521/cpu0`:

| `ZEPHYR_SDK_INSTALL_DIR` | extra CMake argument | rc | `-- Found toolchain:` line |
|---|---|---|---|
| env `/nonexistent` | none | 0 | `zephyr 1.0.1 ($HOME/zephyr-sdk-1.0.1)`: silently another SDK |
| env `/nonexistent` | `-DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF` | 1 on Debian, 0 on macOS | Debian: none; macOS: the same SDK again, found through `PATH` |
| env real SDK | `-DZEPHYR_SDK_INSTALL_DIR=/nonexistent` | 1 | `zephyr 1.0.1 (/nonexistent)`: the version of the SDK it found, the path of the variable |

So turning the package registry off is no defence. The defence is the log:
every `west build` prints `-- Found toolchain: zephyr <version> (<path>)`.
Compare that line with the SDK you meant.

## QEMU

The build's `run` target uses the SDK's QEMU, not the distribution's:
`$ZEPHYR_SDK_INSTALL_DIR/hosttools/sysroots/x86_64-pokysdk-linux/usr/bin/qemu-system-arm`
on Debian and `hosttools/usr/bin/qemu-system-arm` on macOS, both
`QEMU emulator version 10.0.2` (`QEMU:FILEPATH` in the build directory's
`CMakeCache.txt` names it). The Cortex-M33 board runs with
`-cpu cortex-m33 -machine mps2-an521 -icount shift=7,align=off,sleep=off -rtc clock=vm`.
QEMU never exits by itself because Zephyr idles; the lanes stop it at the
console's last line.

## The official LLVM's `ld.lld` on Debian 13

The LLVM 23.1.1 release's `ld.lld` is linked against ICU 70, which Debian 13
does not ship:

```
/opt/llvm-23.1.1/bin/ld.lld: error while loading shared libraries: libicui18n.so.70: cannot open shared object file: No such file or directory
```

The compiler is unaffected. Links through `west build` use the SDK's GNU
linker. Where a lane links with `lld` itself (wasm32, the bare Cortex-M33),
put a directory holding `libicui18n.so.70`, `libicuuc.so.70` and
`libicudata.so.70` in `LD_LIBRARY_PATH`; Ubuntu 22.04's `libicu70` package
has them.
