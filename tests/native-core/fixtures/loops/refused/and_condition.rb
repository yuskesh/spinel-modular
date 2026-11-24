def f(a, b)
  while a > 0 && b > 0
    a -= 1
    b -= 2
  end
  a + b
end
puts f(10, 6)
