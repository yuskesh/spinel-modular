def gcd(a, b)
  while a != b
    if a > b then a -= b else b -= a end
  end
  a
end
puts gcd(0, 5)
