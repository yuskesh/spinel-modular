def fact(n)
  r = 1
  i = 1
  while i <= n
    r = r * i
    i = i + 1
  end
  r
end
puts fact(10)
