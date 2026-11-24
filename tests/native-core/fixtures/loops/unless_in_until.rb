def f(n)
  s = 0
  until n == 0
    unless n % 2 == 0 then s += n else s -= 1 end
    n -= 1
  end
  s
end
puts f(6)
