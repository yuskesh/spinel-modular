def fib(n)
  a = 0
  b = 1
  i = 0
  while i < n
    t = a + b
    a = b
    b = t
    i += 1
  end
  a
end
puts fib(50)
puts fib(100)
