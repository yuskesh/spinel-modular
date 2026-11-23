# Integers, strings, symbols, arrays, hashes, blocks, classes and exceptions.
class Point
  attr_reader :x, :y
  def initialize(x, y)
    @x = x
    @y = y
  end
  def +(other) = Point.new(@x + other.x, @y + other.y)
  def to_s = "(#{@x}, #{@y})"
end

class Empty < StandardError; end

puts 7 / 2, -7 / 2, 7 % 3, 2**10
puts 2**30
begin
  puts 2**30 * 4
rescue RangeError => e
  puts "RangeError: #{e.message}"
end
puts "spinel".upcase + "-" + "M33".downcase
puts "a,b,,c".split(",").inspect
puts "%05d|%-4s|%x" % [42, "ab", 255]
puts :sym.inspect, :sym.to_s.size
a = [5, 3, 9, 1]
puts a.sort.inspect, a.map { |v| v * 2 }.inspect, a.select(&:odd?).inspect, a.sum, a.max
puts (1..5).reduce(:+), (1..4).to_a.reverse.inspect
h = { "one" => 1, "two" => 2 }
h["three"] = 3
puts h.inspect, h.keys.inspect, h.values.sum, h.key?("two"), h.fetch("four", 0)
puts({ a: 1, b: [2, 3] }.inspect)
puts (Point.new(1, 2) + Point.new(10, 20)).to_s
def depth(n) = n.zero? ? 0 : 1 + depth(n - 1)
puts depth(200)
log = []
begin
  begin
    raise Empty, "inner"
  ensure
    log << "ensure"
  end
rescue Empty => e
  log << "rescued #{e.class} #{e.message}"
end
puts log.inspect
r = [1, 2, 3].each_with_index.map { |v, i| v * i }
puts r.inspect
puts [3, 1, 2].sort_by { -_1 }.inspect
