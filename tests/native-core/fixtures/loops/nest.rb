def f(n)
  i = 0
  s = 0
  while i < n
    j = 0
    while j < i
      s += j
      j += 1
    end
    i += 1
  end
  s
end
puts f(10)
