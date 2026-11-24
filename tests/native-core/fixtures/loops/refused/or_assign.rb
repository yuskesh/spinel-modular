def f(n)
  i = 0
  while i < n
    i ||= 3
    i += 1
  end
  i
end
puts f(3)
