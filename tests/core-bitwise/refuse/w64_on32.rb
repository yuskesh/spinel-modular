# tests/core-bitwise/refuse/w64_on32.rb -- a 64-bit
# form on the wasm32 profile's 32-bit body, refused as int64 is: a 32-bit
# target refuses 64-bit integers at once. run.sh compiles it for the wasm32 profile.
require_relative "spinel/freestanding"

freestanding_def :f, params: [:i32, :i32], returns: :i32
def f(a, b)
  core_w64_add(a, b)
end
