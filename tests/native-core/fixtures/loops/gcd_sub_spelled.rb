def gcd(a, b)
  while a != b
    if a > b
      a = a - b
    else
      b = b - a
    end
  end
  a
end
puts gcd(48, 18)
puts gcd(7, 7)
