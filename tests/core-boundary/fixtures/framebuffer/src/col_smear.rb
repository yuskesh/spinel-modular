# Rewrites one column of the screen from its neighbours: each pixel becomes
# the pixel some rows above or below it, passed through one row of the lookup
# table. `offs` holds the row distances, used in turn from `phase` and
# wrapping at `period`. It reads the screen it is writing, so what it draws
# depends on what was drawn before it and on the order it goes in.

def col_smear(scr, n_scr, lut, n_lut, offs, n_offs,
              x, y0, y1, phase, period, row, width)
  base = row * 16
  at = y0 * width + x
  ph = phase
  y = y0
  while y <= y1
    scr[at] = lut[base + scr[at + offs[ph] * width]]
    ph = (ph + 1) % period
    at += width
    y += 1
  end
  0
end
