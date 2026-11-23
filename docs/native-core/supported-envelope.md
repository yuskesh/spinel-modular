# What is implemented, and what is refused

This page covers the `--core` route for an ordinary Ruby method:
`tools/core/spinel-core-build`. The behaviour below was observed on Debian
x86_64 with LLVM/Clang 23.1.1; the suites named at the end keep it checked.

## The commands

```sh
# the whole path
tools/core/spinel-core-build --source app.rb --core <method> -o app

# the pieces, if you need them separately
vendor/spinel/bin/spinel app.rb --core <method> --core-id=<id> --core-map=<map> \
                  --inputs-out=<ledger> --no-line-map -S
tools/mlir/native/build/bin/spinel-core-emit --source app.rb --core-map <map> \
                  -o core.o --clang <clang> [--inputs-out <ledger>]
tools/core/core-artifact-gate core.o <symbol>
tools/mlir/native/build/bin/spinel-core-check app.rb --method <method>
```

Use the driver for the complete checked and linked artifact.

## The admitted source envelope

One file. One selected top-level method. The method and its statically
resolved helpers may use:

- integer literals, including `-9223372036854775808`;
- integer comparison;
- conditional selection;
- local assignment and reads;
- `+ - * / %` and unary `-` on 64-bit integers;
- the bitwise `&`, `|`, `^` and `~`, which are exact and cannot fail;
- `<<` and `>>` under Ruby's rule: a negative count shifts the other way, and
  `>>` by 64 or more is 0 or -1;
- `abs` and `**`; `**` lowers without a loop;
- the named word forms of the intrinsic table
  (`tools/mlir/native/include/spinel-mlir/Core/Intrinsics.h`): the wrapping
  `core_w32_*` and `core_w64_*`, the unsigned `core_u32_*` and `core_u64_*`,
  the fixed-point `core_fixed_mul` and `core_fixed_div`, and the constant
  `core_u32(LIT)`;
- direct calls to other methods in the same closure.

At the top level: method definitions, a direct call into the closure, and
`puts <call into the closure>`. Nothing else. The top level passes only
integer literals to the selected method.

## Failures at run time

Checked arithmetic ends the program as the uncaught Ruby exception would,
with exit status 1:

| operation | message |
|---|---|
| overflow of `+ - * -@` | `integer overflow in *` (RangeError), with the operator |
| a zero divisor | `divided by 0` (ZeroDivisionError) |
| a left shift that loses bits, `a >> -n` included | `integer overflow in <<` (RangeError) |
| `INT64_MIN.abs` | `integer overflow in abs` (RangeError) |
| a power past 64 bits | `integer overflow in **` (RangeError) |
| a negative exponent | `negative exponent` (RangeError) |
| a 32-bit word form's operand outside the i32 range | `core_w32_add: an operand is outside the i32 range` (RangeError), with the form's name |
| a `u32`/`u64` shift count outside 0..31 or 0..63 | `core_u64_shr: the count is outside 0..63` (RangeError), with the form's name |

A `w64` form answers the low 64 bits and cannot fail. `core_u32` takes only
an Integer literal in 0..4294967295; anything else is refused at build time
(`unsupported-intrinsic-call`), and so is a top-level definition of a name
in the intrinsic table (`conflicting-intrinsic`). The driver adds the
definitions the source names from `tools/core/hosted-prelude.rb` to the
hosted copy it compiles, so the hosted half has the names too; the core
object never contains them.

## What is refused at build time

Each of these was built through `spinel-core-build` and refused. The verdict
is the behaviour; the wording may change.

| program | outcome |
|---|---|
| `a < b ? a : nil` | refused: `unsupported-node`, `NilNode` |
| a `Float` argument | refused: `type-evidence`, `parameter a is float` |
| a `String` argument | refused: `type-evidence`, `parameter a is strbuf` |
| a `while` loop | refused: `unsupported-node`, `WhileNode` |
| `[a, b].min` | refused: `unresolved-call`, no scalar effect contract for `min` |
| no caller in the program | refused: `type-evidence`, the parameter has no inferred type |
| a method that is not in the source | refused: not eligible |
| `require "json"` | refused: a load that is recognised and not satisfied from a file |
| a second top-level method calling into the closure, called at the top level | refused: `binding-environment`, the top level supports only definitions and calls into the selected closure |
| `tests/native-core/fixtures/lower.rb` | **accepted**, prints 3 |

The CORE boundary route ([the buffer boundary](../core/buffer-boundary.md))
admits more, under a written contract: loops and lent buffers of integers.
It has no Float either; Float crosses a boundary only on the freestanding
route ([declaring a core boundary](../../tools/freestanding/README.md)).

## Runtime presence in the combined executable

This is not a GC-free program and is not presented as one. The hosted
runtime is linked in by design: startup, output and everything else the
program does outside the selected method still goes through it. What is
independent is the **core object**: `tools/core/core-artifact-gate` checks
that its exports in the core namespace are the mapped symbol only, that the
symbol has code, and that
it leaves no symbol undefined other than the one extern the driver names,
the failure hook `spc_core_fail`. A collector entry point or a runtime
symbol the object needed would be such an undefined symbol. That is checked at the
object boundary rather than inferred from the executable.

## Claims not made

- **Not "Ruby works".** The envelope above is small; most of the language is
  refused.
- **Not a GC-free executable.** See the section above.
- **Not arbitrary input.** The top level passes integer literals; a method
  whose arguments come from anywhere else is not on this route.

## Checks

`tests/native-core/driver.sh` (the driver and its refusals),
`tests/native-core/arith.sh` (arithmetic, shifts, powers and the word forms),
`tests/native-core/ledger.sh` (the ledger of input files) and
`ruby tests/core-eligibility/run.rb` (source eligibility).
