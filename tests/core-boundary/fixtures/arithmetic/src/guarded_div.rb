# Arithmetic reference kernel for the checked scalar mode.
#
# One definition per file. There is no caller and no evidence call: the
# contract declares each parameter's domain, and the checker derives the rest of
# the closure from those facts and validates every use against them.
# The division is not on the executed path when b is zero. An implementation
# that checks operations it did not execute fails this.

def guarded_div(a, b)
  if b == 0
    0
  else
    a / b
  end
end
