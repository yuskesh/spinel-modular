# A refusal fixture for the checked native buffers. Not a case in the descriptor
# table: it exists to be rejected, and buffers.sh declares the diagnostic it
# must be rejected with.

# An `if` with no else, taken AS A VALUE. The false path produces nothing, so
# what the assignment receives is nil, and nil is not in this subset.
#
# Why the shape is this one. A statement-position form such as
#
#     t = link[0]
#     if n_link > 3
#       t = 0
#     end
#     t
#
# is not a nil case: that `if` is in STATEMENT position and `t` already has a
# value on both paths, so it builds. The rule that both arms must exist applies
# in value position only. The form below is a nil case: the `if` IS the value.
#
# This fixture guards a NARROWING. The producer's own `nullable_int` analysis
# answers about hosted Ruby, where `buf[i]` off the end is nil; the checked
# route has no nil there, because the contract declares each buffer's count and
# an access outside it is SPINEL_CORE_BOUNDS. So with facts supplied the
# derivation answers instead -- otherwise the ordinary shape of walking a
# linked structure, where a local read from a buffer is rebound on both arms of
# a branch, was refused for a nil that cannot occur. Walk_links exercises that
# shape; this fixture and nil_while_value are the other half: a value that
# really is nil here must still be refused, and by the derivation.

def nil_if_no_else(link, n_link)
  t = if n_link > 3
        link[0]
      end
  t
end
