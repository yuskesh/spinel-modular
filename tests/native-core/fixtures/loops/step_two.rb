def f(a, b)
  c = 0
  while a <= b
    c += 1
    a += 2
  end
  c
end
puts f(1, 9)
puts f(9, 1)
