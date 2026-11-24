def tri(n)
  s = 0
  i = 0
  while i < n
    i += 1
    s += i
  end
  s
end
def f(a)
  t = 0
  while a > 0
    t += tri(a)
    a -= 1
  end
  t
end
puts f(4)
