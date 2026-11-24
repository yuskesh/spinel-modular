def f(n)
  i = 0
  while i < n
    if i == 3
      return i
    end
    i += 1
  end
  i
end
puts f(10)
