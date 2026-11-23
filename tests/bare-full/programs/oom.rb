# Keeps everything it allocates: with a small heap the runtime must stop with
# its out-of-memory message, not fault or run on.
keep = []
i = 0
loop do
  keep << ("x" * 64) + i.to_s
  i += 1
end
