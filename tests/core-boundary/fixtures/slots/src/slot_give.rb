# Gives slot i back to the pool: it becomes the first slot slot_take hands
# out again, and remembers the one that was first before it.

def slot_give(i, link, n_link, state, n_state)
  link[i] = state[0]
  state[0] = i
  0
end
