# A refusal fixture for the word intrinsics: the intrinsic with a splat argument.

def r(a, b)
  xs = [a, b]
  core_w32_add(*xs)
end
