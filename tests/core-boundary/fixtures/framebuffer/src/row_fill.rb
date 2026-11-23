# Draws one row of the screen, left to right, sampling an eight-entry tile.
# The sample position `u` is 8.8 fixed point (256 is one entry): its integer
# part, taken modulo 8, picks the entry, and it moves on by `du` for each
# pixel, kept to 16 bits. Each sample is passed through one row of the lookup
# table before it is stored.

def row_fill(scr, n_scr, tile, n_tile, lut, n_lut,
             y, x0, x1, u, du, row, width)
  base = row * 16
  at = y * width + x0
  pos = u
  x = x0
  while x <= x1
    scr[at] = lut[base + tile[(pos >> 8) & 7]]
    pos = (pos + du) & 0xffff
    at += 1
    x += 1
  end
  0
end
