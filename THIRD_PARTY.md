# Third-party code and licences

The project's own licence is Apache-2.0 WITH LLVM-exception: see
[`LICENSE`](LICENSE) and [`NOTICE`](NOTICE). It covers every file except those
listed here, which keep the licence named.

| files | licence | licence text | note |
| --- | --- | --- | --- |
| `vendor/spinel` | MIT | (in the linked repository) | a submodule entry; the pinned tree keeps its own notices |
| `tools/contract/spinel_contract.h` | project+MIT | `tools/contract/LICENSE.spinel` | reproduces two Spinel functions (MIT, Yukihiro Matsumoto) beside code written here |
| `tools/contract/LICENSE.spinel` | MIT | `tools/contract/LICENSE.spinel` | Spinel's LICENSE at the pinned revision, byte for byte |
| `tools/bare-full/runtime/shim/**` | MIT+project | `tools/bare-full/runtime/shim/LICENSE.spinel` | stand-ins for POSIX headers, from Spinel's headers for wasm32-wasi at the pinned revision (MIT, Yukihiro Matsumoto) with additions written here; `LICENSE.spinel` is Spinel's LICENSE, byte for byte |

Nothing else in this repository is third-party code. The build links LLVM and
MLIR (Apache-2.0 WITH LLVM-exception) from an installation you provide, and
the target lanes and the bare-metal build use Zephyr, compiler-rt, picolibc
and wasi-sdk the same way; none of
them is vendored here.
