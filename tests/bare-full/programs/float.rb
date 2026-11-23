# Float arithmetic and printing, and picolibc's math through Math.
puts 0.1 + 0.2
puts 1.5 * 4, 10 / 4.0, 7.0 % 3.0, 2.0**10
puts 1.0 / 3, 1e20, 1.0e-5, 100.0, -0.0
puts 3.7.floor, 3.2.ceil, 2.5.round, (-2.5).round, 3.14159.round(2), 1234.5678.truncate
puts Math.sqrt(16.0), Math.sqrt(2.0)
puts Math.sin(0.0), Math.cos(0.0), Math.exp(0.0), Math.log(1.0), Math.log(Math::E)
puts Math::PI, Math.atan2(1.0, 1.0) * 4 == Math::PI
puts Math.log10(1000.0), Math.log2(8.0), Math.hypot(3.0, 4.0)
puts (0.1 * 3).round(15), 5.fdiv(2), 2.0.to_i + 1, "3.25".to_f * 2
puts [1.5, 0.25, 2.0].sum, [3.5, 1.25].max, 1.0.nan?, (0.0 / 0.0).nan?, (1.0 / 0.0)
