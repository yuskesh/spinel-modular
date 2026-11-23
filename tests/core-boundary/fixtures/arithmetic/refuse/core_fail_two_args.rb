# A refusal fixture for the checked scalar mode. Not a case in the table: it
# exists to be rejected, and arithmetic.sh declares the diagnostic it must be
# rejected with.

# One argument, and it is the category.

def two_args(a, b)
  if b == 0
    core_fail(:capacity, a)
  else
    a + b
  end
end
