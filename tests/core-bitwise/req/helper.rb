# tests/core-bitwise/req/helper.rb -- a required
# file whose method calls an intrinsic. req/main.rb names no intrinsic itself.
def helper(a, b)
  core_w32_add(a, b)
end
