# A 64-bit value read as a signed 32-bit one: the low 32 bits, two's
# complement. The value is biased by 2^31 so that the masked result runs from
# 0 to 2^32 - 1 in the order of the signed answers, and the bias is taken off
# again.

def wrap_i32(v)
  ((v + 0x80000000) & 0xffffffff) - 0x80000000
end
