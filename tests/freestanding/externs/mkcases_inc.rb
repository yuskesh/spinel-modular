#!/usr/bin/env ruby
# frozen_string_literal: true
#
# mkcases_inc.rb -- generates the `cases.inc` that the Zephyr driver
# `zephyr/src/main.c` includes, from the tracked `cases.json`.
#
#   ruby mkcases_inc.rb cases.json > gen/cases.inc
require "json"

spec = JSON.parse(File.read(ARGV.fetch(0)))
out = ["static void externs_run(void) {"]
spec.fetch("cases").each do |c|
  conv = { "int" => "EXTERNS_CASE_I", "float" => "EXTERNS_CASE_F" }.fetch(c["kind"])
  args = c["args"].map { |a| a["t"] == "i64" ? "INT64_C(#{a['v']})" : a["v"].to_s }
  out << "\t#{conv}(\"#{c['name']}\", #{c['sym']}(#{args.join(', ')}));"
end
out << "}"
puts out.join("\n")
