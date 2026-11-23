# A word-arithmetic case for tests/native-core/arith.sh: a `core_u64_shr` count
# outside 0..63 fails.
def calculate(a, b)
  core_u64_shr(a, b)
end

puts calculate(-1, 64)
