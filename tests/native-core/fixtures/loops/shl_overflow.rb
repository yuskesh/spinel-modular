def f(n)
  s = 1
  while n > 0
    s <<= 1
    n -= 1
  end
  s
end
puts f(62)
puts f(63)
