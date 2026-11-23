#!/usr/bin/env ruby
# frozen_string_literal: true
#
# probe/sig.json -- the worker's view of the boundary, generated from the
# same header the C side would compile against.  The JSON has a one-space
# indent and NO trailing newline.
#
#   ruby mksig.rb <spinel_freestanding.h> <out.json>
#
# index.mjs must not contain a transcribed signature list for the same reason
# a shim table is generated: a transcription that can be wrong is a bug
# generator.
require_relative "mkcases_wasm"

sig = {}
MkcasesWasm.header_types(ARGV[0]).sort.each do |name, (ps, ret)|
  sig[name] = {
    "export" => name, "params" => ps, "returns" => ret,
    "big" => ps.map { |p| MkcasesWasm::BIG.include?(p) },
    "retbig" => MkcasesWasm::BIG.include?(ret),
  }
end
File.write(ARGV[1], MkcasesWasm.emit_json(sig))
puts format("probe/sig.json: %d exported boundaries", sig.length)
