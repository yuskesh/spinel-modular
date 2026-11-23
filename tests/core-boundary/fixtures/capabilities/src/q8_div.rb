# The quotient of two Q24.8 numbers (256 is 1.0), rounded toward zero and
# clamped to the 32-bit range. A zero divisor answers the limit on the
# dividend's side, so the entry never divides by zero.

Q8_MIN = -2147483648
Q8_MAX = 2147483647

def q8_div(a, b)
  if b == 0
    a < 0 ? Q8_MIN : Q8_MAX
  else
    n = a * 256
    q = n.abs / b.abs
    if n < 0
      q = b < 0 ? q : -q
    else
      q = b < 0 ? -q : q
    end
    if q > Q8_MAX
      Q8_MAX
    else
      q < Q8_MIN ? Q8_MIN : q
    end
  end
end
