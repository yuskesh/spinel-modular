# Building a native core executable

`tools/core/spinel-core-build` takes one Ruby source and the name of one of
its top-level methods, checks that the method's whole call closure is `core`,
compiles that closure to a native object, and links it into the hosted
executable in place of the runtime's version of the method.

## Build from the repository root

Select LLVM 23.1.1 and a CRuby interpreter on PATH. On Debian, the measured
LLVM prefix is `/opt/llvm-23.1.1`. On macOS, use the installation described
in the
[installation record](../toolchains/llvm-23.1.1-macos/INSTALLATION-RECORD.md),
for example `$HOME/.local/opt/llvm-23.1.1`, and install Xcode's macOS SDK.

```sh
export LLVM_PREFIX=/opt/llvm-23.1.1  # use your installation prefix on macOS
export CLANG="$LLVM_PREFIX/bin/clang"
export CC="$CLANG"
export NM="$LLVM_PREFIX/bin/llvm-nm"
umask 022
git submodule update --init --recursive
make -C vendor/spinel deps
make -C vendor/spinel -j8 CC="$CC"
tools/contract/build.sh
tools/mlir/native/build.sh
mkdir -p build
tools/core/spinel-core-build --source tests/native-core/fixtures/lower.rb \
  --core lower -o build/lower.bin
./build/lower.bin
```

Expected output: `3`. `SPINEL_CORE_VERBOSE=1` prints the six build stages:
the source snapshot, the eligibility check, the core symbol, the core object,
the artifact gate and the link.

On macOS the native build uses the SDK's libc++ headers with the system
libc++ runtime, while compiling against LLVM/MLIR 23.1.1. Use a fresh
`BUILD_DIR` when changing toolchains, and set `SPINEL_CORE_BUILD` to that
same directory for the driver and the tests.

The driver uses the compiler in `vendor/spinel`. `SPINEL_SEAM` and
`SPINEL_TYPEDUMP` are optional overrides for development.

## Checks

```sh
tests/native-core/driver.sh
tests/native-core/ledger.sh
tests/native-core/arith.sh
tests/native-core/loops.sh
ruby tests/core-eligibility/run.rb
```

`LLVM_PREFIX` (or `NM`) and `CLANG` are required for these checks.
`tools/core/core-artifact-gate` reads the object's symbol table through `NM`,
defaulting to `$LLVM_PREFIX/bin/llvm-nm`, and refuses to start with
`set LLVM_PREFIX or NM` if neither is set. `tests/native-core/ledger.sh`
defaults `--clang` to `/opt/llvm-23.1.1/bin/clang`, which does not exist on
macOS; the export block above sets all of them.

Also run `tests/native-core/run.sh`, on either host, and on Debian
`tests/core/run.sh` for the declared freestanding checks. `tests/core/run.sh`
selects the x86_64-linux freestanding profile, links its objects into host
programs and runs them, so on any other host it says SKIP and exits 2. On
macOS arm64, also run `ruby tests/native-core/macos-probe.rb` for the Mach-O
fixture checks.

The driver suite exercises the artifact gate on both hosts, including
unexpected exports, undefined dependencies, non-code exports and a failing
symbol reader.

## Scope

The executable contains the normal hosted runtime. Only the core object is
checked for runtime independence. The route takes one source file and one
selected top-level method; the [supported envelope](supported-envelope.md)
says what the method may contain.

Builds on Debian x86_64 and macOS arm64 are native builds. This is not a
cross compiler or a hermetic build: the system toolchain, SDK and C library
headers remain environmental inputs. The driver records the selected SDK
path and deployment-target setting; it does not hash SDK contents.
