# Arithmetic reference kernel for the checked scalar mode.
#
# One definition per file, plus any helpers it calls, and no caller anywhere:
# the contract declares each parameter's domain and the checker derives the
# rest of the closure from those facts.

# Early return is admitted: a `return` anywhere in a checked closure must not
# be refused as an unsupported node.

def early_return(a, b)
  if b == 0
    return 1
  else
    return a + b
  end
end
