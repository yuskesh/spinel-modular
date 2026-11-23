# tests/core-bitwise/lines/lines.rb -- the intrinsics' prelude
# goes before the program, after these comment lines; the module's
# locations are still this file's own lines (part 9 of run.sh).
require_relative "spinel/freestanding"

freestanding_def :f, params: [:i64], returns: :i64
def f(a)
  b = core_w32_add(a, 1)
  b * 3
end
