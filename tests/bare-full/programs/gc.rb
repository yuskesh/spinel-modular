# Many short lives and a few long ones: collections must run, and the
# survivors must come through them intact.
class Cell
  attr_reader :v
  def initialize(v) = (@v = v)
end
keep = []
total = 0
300.times do |r|
  batch = Array.new(40) { |i| Cell.new(r * 40 + i) }
  total += batch.sum(&:v)
  keep << Cell.new(r) if r % 10 == 0
  keep << ("k" + r.to_s) if r % 50 == 0
end
s = +""
200.times { |i| s << (i % 10).to_s }
words = (1..400).map { |i| "w#{i}" }
puts total
puts keep.size, keep.grep(Cell).sum(&:v), keep.grep(String).join(" ")
puts s.size, s[0, 12], words.last, words.map(&:size).sum
