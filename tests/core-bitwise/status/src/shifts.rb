# tests/core-bitwise/status/src/shifts.rb -- the shifts on the
# status lane: one kernel per method, built by run.sh from a contract that
# declares both parameters at the body width.

def shl(a, n)
  a << n
end

def shr(a, n)
  a >> n
end
