#!/usr/bin/env ruby
# frozen_string_literal: true
#
# The `ints` lane's case table: the MCU cases and the host comparison both
# come from it.
#
#   ruby mkcases.rb [<outdir>]              # ints_host.rb + cases.inc + expect.tsv
#   ruby mkcases.rb --host <kern> <out>     # only the host driver (for a comparison made by hand)
#
# The host oracle (`ints_host.rb`, compiled by bin/spinel through its ordinary C
# back end) and the MCU program (`cases.inc`, compiled into the Zephyr app) have
# to call the same methods with the same arguments, or the comparison means
# nothing.  Writing the list twice guarantees they drift, so it is written once,
# here, and both sides are generated from it.
#
# The Ruby METHOD BODIES are not written here at all: `ints_host.rb` is
# `ints_kern.rb` with the two declaration lines deleted and a driver appended, so
# the bodies are byte-identical to what spinel-fs-emit compiled.
#
# `expect` is the CONTRACT, not an observation:
#
#   same     the host (i64 everywhere, C back end) and the MCU (a 32-bit body
#            on every target built here) must print the same characters.
#   diverge  the two are REQUIRED to differ, and the reason is a rule:
#            a value that does not fit the 32-bit body or the declared boundary
#            traps on the MCU where the host, whose Integer is 64-bit and then arbitrary
#            precision, just keeps computing.  A `diverge` row that came out
#            `same` is as much a failure as the other way round.

# Everything lives in a module so that requiring this file from the wasm lane's
# mkcases_wasm.rb cannot collide with that file's own names (Ruby's top level
# is shared).
module Mkcases
  module_function

  HERE = File.dirname(File.expand_path(__FILE__))

  # (name, ruby expression, C expression, expect)
  CASES = [
    # --- the first case: add(a, b) on an MCU -----------
    ["add(20,22)",            "add(20, 22)",            "spinel_add(20, 22)", "same"],
    ["add(-1,1)",             "add(-1, 1)",             "spinel_add(-1, 1)", "same"],
    ["add(2147483647,0)",     "add(2147483647, 0)",     "spinel_add(2147483647, 0)", "same"],
    # i32 arguments, i32 body: the sum overflows the body itself, before the
    # boundary sees it.
    ["add(2147483647,1)",     "add(2147483647, 1)",     "spinel_add(2147483647, 1)", "diverge"],

    # --- fib, igcd and sumsq, at an i32 boundary ----------------------------
    ["fib(20)",               "fib(20)",                "spinel_fib(20)", "same"],
    ["fib(30)",               "fib(30)",                "spinel_fib(30)", "same"],
    ["igcd(-270,192)",        "igcd(-270, 192)",        "spinel_igcd(-270, 192)", "same"],
    ["igcd(12,-18)",          "igcd(12, -18)",          "spinel_igcd(12, -18)", "same"],
    ["igcd(1071,462)",        "igcd(1071, 462)",        "spinel_igcd(1071, 462)", "same"],
    ["sumsq(10)",             "sumsq(10)",              "spinel_sumsq(10)", "same"],
    ["sumsq(100)",            "sumsq(100)",             "spinel_sumsq(100)", "same"],

    # --- the i32 product ---------------------------------------------------
    # mulwide, its :i64 twin, is in ints_wide.rb and runs on a 64-bit host
    # only (run_wide.sh).
    ["mulnarrow(46340,46340)", "mulnarrow(46340, 46340)",
     "spinel_mulnarrow(46340, 46340)", "same"],
    ["mulnarrow(46341,46341)", "mulnarrow(46341, 46341)",
     "spinel_mulnarrow(46341, 46341)", "diverge"],
    # overflow: :wrap -- declared, therefore not a surprise.
    ["mulwrap(46341,46341)",  "mulwrap(46341, 46341)",  "spinel_mulwrap(46341, 46341)",
     "diverge"],

    # --- floored division, and the zero divisor -----------------------------
    ["qdiv(7,2)",             "qdiv(7, 2)",             "spinel_qdiv(7, 2)", "same"],
    ["qdiv(-7,2)",            "qdiv(-7, 2)",            "spinel_qdiv(-7, 2)", "same"],
    ["qdiv(7,-2)",            "qdiv(7, -2)",            "spinel_qdiv(7, -2)", "same"],
    ["qdiv(1,0)",             "qdiv(1, 0)",             "spinel_qdiv(1, 0)", "diverge"],

    # --- the C ABI itself ---------------------------------------------------
    # FOUR i32 parameters: r0-r3 under AAPCS.  An i64 boundary would spill and
    # the answer would be wrong, so this case discriminates the two ABIs.
    ["abi4(1000,1,100000,7)", "abi4(1000, 1, 100000, 7)",
     "spinel_abi4(1000, 1, 100000, 7)", "same"],
    ["abi4(-5,-6,-7,-8)",     "abi4(-5, -6, -7, -8)",   "spinel_abi4(-5, -6, -7, -8)", "same"],
    # Sign extension of the most negative i32, and a result one below INT32_MIN.
    ["abi4(-2147483648,1,0,0)", "abi4(-2147483648, 1, 0, 0)",
     "spinel_abi4(-2147483648, 1, 0, 0)", "diverge"],

    # --- narrow and unsigned boundaries -------------------------------------
    ["u8clamp(200,55)",       "u8clamp(200, 55)",       "spinel_u8clamp(200, 55)", "same"],
    ["u8clamp(200,56)",       "u8clamp(200, 56)",       "spinel_u8clamp(200, 56)", "diverge"],
    ["i8neg(100)",            "i8neg(100)",             "spinel_i8neg(100)", "same"],
    ["i8neg(128)",            "i8neg(128)",             "spinel_i8neg(128)", "same"],
    ["i8neg(-128)",           "i8neg(-128)",            "spinel_i8neg(-128)", "diverge"],
    ["abi_version()",         "ver",                    "spinel_abi_version()", "same"],
  ].freeze

  # ints_kern.rb -> ints_host.rb: drop the declarations, append a driver that
  # prints ONE case (selected by ARGV[0]) so that a case which raises does not
  # take the rest of the table with it.
  def make_host(kern, out)
    kept = []
    dropped = []
    File.open(kern, "r") do |f|
      f.each_line do |line|
        if line =~ /\A\s*freestanding_def\b/ ||
           line =~ /\A\s*require_relative\s+"spinel\/freestanding"/
          dropped << line
          next
        end
        kept << line
      end
    end
    body = kept.join
    drv = ["", "# --- appended by mkcases.rb: the HOST side of the differential oracle.",
           "# One case per process: `qdiv(1, 0)` raises, and a raise must not be able",
           "# to hide the rows after it.",
           "_i = ARGV[0].to_i"]
    CASES.each_with_index do |(name, rb, _c, _e), i|
      drv << format("%s _i == %d", i.zero? ? "if" : "elsif", i)
      drv << format('  puts "%s\\t" + (%s).to_s', name, rb)
    end
    drv << "else"
    drv << '  puts "?"'
    drv << "end"
    File.open(out, "w") do |f|
      f.write(body)
      f.write(drv.join("\n") + "\n")
    end
    dropped
  end

  def make_inc(out)
    File.open(out, "w") do |f|
      f.write("/* Generated by mkcases.rb -- do not edit. The MCU side of the\n" \
              "   differential oracle; the host side is ints_host.rb, from the same\n" \
              "   table. */\n")
      CASES.each do |name, _rb, c, _e|
        f.write(format("INTS_CASE(\"%s\", %s)\n", name, c))
      end
    end
  end

  def make_expect(out)
    File.open(out, "w") do |f|
      f.write("idx\tcase\texpect\n")
      CASES.each_with_index do |(name, _rb, _c, e), i|
        f.write(format("%d\t%s\t%s\n", i, name, e))
      end
    end
  end

  def main
    # `--host` writes only the host driver, to the path given, so that nothing
    # is written into this directory.
    if ARGV[0] == "--host"
      unless ARGV.length == 3
        warn "usage: mkcases.rb --host <ints_kern.rb> <out>"
        exit 2
      end
      dropped = make_host(ARGV[1], ARGV[2])
      puts format("host driver: dropped %d declaration line(s)", dropped.length)
      return
    end
    outdir = ARGV.length > 0 ? ARGV[0] : HERE
    kern = File.join(HERE, "ints_kern.rb")
    host = File.join(outdir, "ints_host.rb")
    dropped = make_host(kern, host)
    make_inc(File.join(outdir, "cases.inc"))
    make_expect(File.join(outdir, "expect.tsv"))
    same = CASES.count { |c| c[3] == "same" }
    puts format("mkcases: %d cases (%d same / %d diverge); dropped %d declaration line(s) " \
                "from ints_kern.rb", CASES.length, same, CASES.length - same, dropped.length)
  end
end

Mkcases.main if __FILE__ == $PROGRAM_NAME
