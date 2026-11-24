def mx(n)
  m = 0
  i = 0
  while i < n
    x = i * 7 % 5
    if x > m
      m = x
    end
    i += 1
  end
  m
end
puts mx(10)
