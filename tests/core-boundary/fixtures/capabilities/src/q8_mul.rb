# The product of two Q24.8 numbers (256 is 1.0), wrapped to 32 bits: the
# 64-bit product loses its low 8 fraction bits, rounding toward negative
# infinity, and the low 32 bits of that are read as signed.

def q8_mul(a, b)
  p = (a * b) >> 8
  ((p + 0x80000000) & 0xffffffff) - 0x80000000
end
