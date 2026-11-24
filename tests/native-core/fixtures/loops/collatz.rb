def step(x)
  x * 3 + 1
end
def collatz(n)
  c = 0
  while n != 1
    if n % 2 == 0 then n = n / 2 else n = step(n) end
    c += 1
  end
  c
end
puts collatz(27)
