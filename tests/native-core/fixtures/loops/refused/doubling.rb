def f(n)
  s = 1
  i = 0
  while i < n
    s = s * 2
    i += 1
  end
  s
end
puts f(10)
