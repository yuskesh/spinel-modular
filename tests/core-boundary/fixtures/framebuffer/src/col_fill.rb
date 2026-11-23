# Draws one column of the screen, top to bottom, from a repeating pattern.
# The pattern position starts at `start`, moves on by `step` for each row and
# wraps at `period`. Each pattern value is passed through one row of the
# lookup table (16 entries a row) before it is stored.

def col_fill(scr, n_scr, pat, n_pat, lut, n_lut,
             x, y0, y1, start, step, period, row, width)
  base = row * 16
  at = y0 * width + x
  p = start
  y = y0
  while y <= y1
    scr[at] = lut[base + pat[p]]
    p = (p + step) % period
    at += width
    y += 1
  end
  0
end
