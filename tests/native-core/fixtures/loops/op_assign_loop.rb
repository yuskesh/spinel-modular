def mix(n)
  x = 1000000
  i = 0
  while i < n
    x /= 3
    x %= 100000
    x >>= 1
    x &= 65535
    x |= 4
    x ^= 1
    i += 1
  end
  x
end

puts mix(0)
puts mix(1)
puts mix(3)
