# `<<` on a boxed value: sp_poly_shl keeps the runtime's IO and Queue arms
# reachable (send, getsockopt, fcntl, poll, nanosleep), which the platform
# must define for the program to link. Then sleep, which waits on the clock:
# the time read before and after it must have moved forward by at least the
# requested 250 ms (and by less than a second).
a = [[1, "x"], [2, "y"]]
a.each do |n, s|
  puts((n & 15) << 12)
end
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
sleep 0.25
t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
d = ((t1 - t0) * 1000).to_i
puts(d >= 250 && d < 1000 ? "slept" : "slept #{d} ms")
