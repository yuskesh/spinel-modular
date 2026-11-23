# tests/core-bitwise/status/src/st_u32_wide.rb --
# `core_u32` of a literal past 0..4294967295.

def st_u32_wide(a, n)
  core_u32(4294967296)
end
