# tests/core-bitwise/refuse/u32_wide.rb -- `core_u32`
# of a literal past 0..4294967295.
require_relative "spinel/freestanding"

freestanding_def :f, params: [:i64], returns: :i64
def f(a)
  core_u32(4294967296)
end
