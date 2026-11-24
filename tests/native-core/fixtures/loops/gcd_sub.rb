def gcd(a, b)
  while a != b
    if a > b
      a -= b
    else
      b -= a
    end
  end
  a
end

puts gcd(9, 9)
puts gcd(21, 15)
puts gcd(15, 21)
puts gcd(48, 18)
