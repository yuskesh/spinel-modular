# Arithmetic reference kernel for the checked scalar mode.
#
# One definition per file. There is no caller and no evidence call: the
# contract declares each parameter's domain, and the checker derives the rest of
# the closure from those facts and validates every use against them.
# The multiplication is on the branch that is NOT taken when b is zero.
# Operations are checked on the executed control-flow path only, so
# an implementation that checks both arms refuses an input it must accept.

def guard_untaken(a, b)
  if b == 0
    a
  else
    a * a
  end
end
