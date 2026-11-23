# A refusal fixture for the word intrinsics: the intrinsic given a Boolean.

def r(a, b)
  core_w32_add(a, b == 0)
end
