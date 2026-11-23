# A word-arithmetic case for tests/native-core/arith.sh: five rows of
# `core_w32_shl(a, b)`.
def calculate(a, b)
  core_w32_shl(a, b)
end

puts calculate(1, 31)
puts calculate(1, 32)
puts calculate(-1, 31)
puts calculate(-2147483648, -31)
puts calculate(5, -100)
