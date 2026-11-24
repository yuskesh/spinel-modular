def f(n)
  k = n
  while k > 0
    k -= 1
    n += k
  end
  n
end
puts f(5)
