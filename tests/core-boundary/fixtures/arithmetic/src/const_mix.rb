# Arithmetic reference kernel for the checked scalar mode.
#
# One definition per file. There is no caller and no evidence call: the
# contract declares each parameter's domain, and the checker derives the rest of
# the closure from those facts and validates every use against them.
# Literal scalar constants in the new mode.

def const_mix(a)
  a * 2 + 3
end
