def ops(a, b)
  x = a
  x += b
  x -= 1
  x *= 3
  x /= 2
  x %= 1000
  x <<= 2
  x >>= 1
  x &= 255
  x |= 1
  x ^= 3
  x **= 2
  x
end

puts ops(10, 5)
