def f(n)
  i = 0
  s = 0
  while i < n
    i += 1
    if i % 2 == 0
      next
    end
    s += i
  end
  s
end
puts f(10)
