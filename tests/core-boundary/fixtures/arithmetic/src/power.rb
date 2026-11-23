# Arithmetic reference kernel for the checked scalar mode.
#
# One definition per file. There is no caller and no evidence call: the
# contract declares each parameter's domain, and the checker derives the rest of
# the closure from those facts and validates every use against them.
# `**`: the exact power, or ARITHMETIC where it is past the width or the
# exponent is negative (Ruby's answer there would be a Bignum or a
# Rational).

def power(a, b)
  a**b
end
