# Hands out one slot of a fixed pool. A slot that was given back is reused
# first, newest first: state[0] is the most recently returned slot, or -1, and
# link[i] is the one returned before slot i. Otherwise the next slot never
# used is taken: state[1] counts them. With nothing returned and none unused
# the pool is full.

def slot_take(link, n_link, state, n_state)
  back = state[0]
  fresh = state[1]
  full = 0
  if back < 0
    full = fresh >= n_link ? 1 : 0
  else
    full = 0
  end
  if full == 1
    core_fail(:capacity)
  else
    if back < 0
      state[1] = fresh + 1
      fresh
    else
      state[0] = link[back]
      back
    end
  end
end
