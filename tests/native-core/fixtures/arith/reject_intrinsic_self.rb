# A word-arithmetic case for tests/native-core/arith.sh: refused, an
# intrinsic called with a receiver.
def calculate(a, b)
  self.core_w64_add(a, b)
end

puts calculate(1, 2)
