def f(n)
  i = 0
  while i < n
    break 7 if i == 2
    i += 1
  end
  i
end
puts f(3)
