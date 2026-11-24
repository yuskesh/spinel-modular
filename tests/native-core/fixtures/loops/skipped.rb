def f(n)
  while n > 100
    n -= 1
  end
  n
end
puts f(5)
puts f(-9223372036854775808)
