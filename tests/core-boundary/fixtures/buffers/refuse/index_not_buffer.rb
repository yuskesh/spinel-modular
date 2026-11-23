# A refusal fixture for the checked native buffers. Not a case in the descriptor
# table: it exists to be rejected, and buffers.sh declares the diagnostic it
# must be rejected with.

# `[]` on something that is not a declared buffer parameter. Indexable Ruby
# objects are heap objects, and there is no heap here.

def index_not_buffer(src, n_src)
  xs = 1
  xs[0] + n_src
end
