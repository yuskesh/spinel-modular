# tests/core-bitwise/refuse/def_w64.rb -- a top-level
# definition of an intrinsic's name, never called: the prelude would define
# the same name for the analysis.
require_relative "spinel/freestanding"

def core_w64_add(a, b)
  a + b
end

freestanding_def :f, params: [:i64, :i64], returns: :i64
def f(a, b)
  a - b
end
