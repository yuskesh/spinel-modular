# A word-arithmetic case for tests/native-core/arith.sh: refused, `core_u32`
# of a parameter.
def calculate(a)
  core_u32(a)
end

puts calculate(1)
