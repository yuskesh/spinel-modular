def mx(n)
  m = 0
  i = 0
  while i < n
    x = i * 7 % 5
    m = x if x > m
    i += 1
  end
  m
end
puts mx(10)
