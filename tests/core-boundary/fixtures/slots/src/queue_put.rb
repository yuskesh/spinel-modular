# Appends slot i, carrying `value`, to a first-in first-out queue threaded
# through `nxt`. q[0] is the oldest slot, q[1] the newest (both -1 when the
# queue is empty) and q[2] the length. Answers the new length.

def queue_put(i, value, vals, n_vals, nxt, n_nxt, q, n_q)
  vals[i] = value
  nxt[i] = -1
  last = q[1]
  if last < 0
    q[0] = i
  else
    nxt[last] = i
  end
  q[1] = i
  q[2] = q[2] + 1
  q[2]
end
