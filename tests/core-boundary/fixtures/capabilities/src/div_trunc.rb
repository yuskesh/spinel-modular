# Division that rounds toward zero, as C's `/` does. Ruby's Integer#/ rounds
# toward negative infinity, so the magnitudes are divided and the sign is put
# back.

def div_trunc(n, d)
  q = n.abs / d.abs
  if n < 0
    d < 0 ? q : -q
  else
    d < 0 ? -q : q
  end
end
