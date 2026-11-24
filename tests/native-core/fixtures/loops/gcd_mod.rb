def gcd(a, b)
  while b != 0
    t = b
    b = a % b
    a = t
  end
  a
end
puts gcd(1071, 462)
puts gcd(5, 0)
