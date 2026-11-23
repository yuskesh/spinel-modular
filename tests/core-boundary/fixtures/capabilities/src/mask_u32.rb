# The low 32 bits of a 64-bit value, unsigned: 0 to 4294967295. The answer
# does not fit an i32, so the entry answers i64.

def mask_u32(v)
  v & 0xffffffff
end
