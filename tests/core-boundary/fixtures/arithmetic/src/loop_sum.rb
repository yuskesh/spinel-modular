# Arithmetic reference kernel for the checked scalar mode.
#
# One definition per file. There is no caller and no evidence call: the
# contract declares each parameter's domain, and the checker derives the rest of
# the closure from those facts and validates every use against them.
# A loop whose every iteration is a checked addition.

def loop_sum(a, b)
  i = 0
  total = 0
  while i < b
    total = total + a
    i = i + 1
  end
  total
end
