# spinel: int64
# The `ints` kernel's i64 boundaries, kept apart from ints_kern.rb because a
# 32-bit target does not accept a 64-bit body.
# run_wide.sh builds it for the 64-bit host only.
require_relative "spinel/freestanding"

# i64 return with i32 arguments: the product of two i32 CANNOT overflow the i64
# body, so nothing here can trap -- the widths make the check unnecessary and
# the generator emits none.
freestanding_def :mulwide, params: [:i32, :i32], returns: :i64
def mulwide(a, b)
  a * b
end

# An i64 boundary on BOTH sides, so that the i64 body itself can be made to
# overflow: this is the only way to reach trap code 1 (as opposed to code 3,
# which is the boundary refusing a value that does not fit).
freestanding_def :bigmul, params: [:i64, :i64], returns: :i64
def bigmul(a, b)
  a * b
end
