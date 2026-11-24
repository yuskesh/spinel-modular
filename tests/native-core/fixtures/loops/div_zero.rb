def f(a, n)
  while n >= 0
    a = 100 / n
    n -= 1
  end
  a
end
puts f(1, 3)
