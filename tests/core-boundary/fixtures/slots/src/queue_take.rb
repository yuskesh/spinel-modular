# Removes the oldest slot from the queue and answers it; the caller reads its
# value from `vals`. An empty queue has nothing to answer.

def queue_take(nxt, n_nxt, q, n_q)
  first = q[0]
  if first < 0
    core_fail(:capacity)
  else
    after = nxt[first]
    q[0] = after
    if after < 0
      q[1] = -1
    else
      q[1] = q[1]
    end
    q[2] = q[2] - 1
    first
  end
end
