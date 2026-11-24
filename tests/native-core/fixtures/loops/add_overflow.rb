def acc(n)
  s = 9223372036854775800
  i = 0
  while i < n
    s += i
    i += 1
  end
  s
end
puts acc(3)
puts acc(10)
