#!/usr/bin/env ruby
# frozen_string_literal: true
#
# tests/port-contract: the control chip family's own object.
#
#   object.rb --board BOARD.yaml --header bf-board.h --out DIR -- CC [FLAG...]
#
# It makes DIR/chip-head.o, section .boot2: BF_CHIP_FLASH_HEAD_BYTES bytes
# that start with the board's crystal frequency. It prints the object's path.
require "open3"

opts = {}
args = ARGV.dup
opts[args.shift] = args.shift until args.empty? || args.first == "--"
args.shift
abort "tchip head: usage: object.rb --board BOARD.yaml --header bf-board.h --out DIR -- CC [FLAG...]" unless
  args.any? && %w[--board --header --out].all? { |k| opts[k] }
src = File.join(opts["--out"], "head.S")
File.write(src, ".section .boot2, \"a\"\n.word BF_BOARD_CLOCK_CRYSTAL_HZ\n.space BF_CHIP_FLASH_HEAD_BYTES - 4\n")
obj = File.join(opts["--out"], "chip-head.o")
out, st = Open3.capture2e(*args, "-include", opts["--header"], "-c", src, "-o", obj)
abort "tchip head: #{out}" unless st.success?
puts obj
