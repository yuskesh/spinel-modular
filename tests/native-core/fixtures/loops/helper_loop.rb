def tri(n)
  s = 0
  i = 0
  while i < n
    i += 1
    s += i
  end
  s
end
def f(a, b)
  tri(a) + tri(b)
end
puts f(3, 4)
