# Unlinks every slot whose value is `value`, keeping the others in order, and
# answers how many it unlinked. An unlinked slot's value becomes DROPPED. The
# walk takes at most one step per slot the queue could hold; a chain longer
# than that closes on itself, and the entry stops instead of walking it
# forever.

DROPPED = -1

def queue_drop(value, vals, n_vals, nxt, n_nxt, q, n_q)
  gone = 0
  steps = 0
  looped = 0
  before = -1
  at = q[0]
  while at >= 0
    after = nxt[at]
    if steps >= n_nxt
      looped = 1
      after = -1
    else
      if vals[at] == value
        if before < 0
          q[0] = after
        else
          nxt[before] = after
        end
        if after < 0
          q[1] = before
        else
          q[1] = q[1]
        end
        vals[at] = DROPPED
        q[2] = q[2] - 1
        gone = gone + 1
      else
        before = at
      end
    end
    steps = steps + 1
    at = after
  end
  if looped == 1
    core_fail(:capacity)
  else
    gone
  end
end
