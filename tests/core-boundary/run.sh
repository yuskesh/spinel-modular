#!/bin/sh
#
# tests/core-boundary/run.sh — every CORE boundary lane, with its counts and
# its status.
#
#   tests/core-boundary/run.sh                 run them all
#   REQUIRE_ALL=1 tests/core-boundary/run.sh   and a lane that could not run
#                                              is a failure rather than a note
#
# THREE OUTCOMES, not two. A lane that PASSED and a lane that COULD NOT RUN are
# different answers, and a summary that folded them together would report a
# clean sweep on a machine where half of it never executed. A lane says what it
# needs before it starts, and this file counts a lane that said so separately.
#
# Each lane's own summary line is printed verbatim. They are not reformatted
# into a common shape, because they do not measure a common thing: `arithmetic`
# counts executed cases, `artifacts` counts entries over capabilities, and a
# run.sh that flattened them into "N passed" would be discarding the part that
# says what was measured.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HERE="$ROOT/tests/core-boundary"

# In the order they were built: the boundary, then the two
# checked lanes, then the adapter, then the three capabilities, then the lane
# that asks about all of them at once and the one that probes the subset; then the word intrinsics,
# on this host and, for a 32-bit body, under QEMU's mps2-an521 (which does not
# start without qemu-system-arm and compiler-rt's builtins for ARMv8-M); then
# the kernel's failure sites, a debugging aid.
LANES="schema arithmetic buffers adapter capabilities framebuffer slots artifacts constructs intrinsics intrinsics-32 failure-sites"
EXPECT_LANES=12

# REQUIRE_ALL is read here AND by the lanes: a lane that ran but whose
# sub-lanes could not (no thread sanitiser, no pinned compiler, a sanitiser
# that would not build) still prints a summary and exits 0, and this file
# cannot tell that from a clean run. Exported so it reaches them whether it was
# set in the environment or assigned to this script.
REQUIRE_ALL="${REQUIRE_ALL:-0}"
export REQUIRE_ALL

pass=0; fail=0; notrun=0
run_out="$(mktemp "${TMPDIR:-/tmp}/core-run.XXXXXX")"
trap 'rm -f "$run_out"' EXIT INT TERM

# Every lane in LANES is there, and every lane that is there is in LANES. A
# declared list with nothing tying it to the directory drops a lane silently;
# this one has done that before, in another file, and been caught for it.
declared=$(printf '%s\n' $LANES | sort | tr '\n' ' ')
present=$(for f in "$HERE"/*.sh; do b=$(basename "$f" .sh); [ "$b" = run ] || echo "$b"; done | sort | tr '\n' ' ')
if [ "$declared" != "$present" ]; then
  echo "core-boundary: declared [$declared] but the directory holds [$present]" >&2
  exit 1
fi
n_declared=$(echo $LANES | wc -w | tr -d ' ')
if [ "$n_declared" -ne "$EXPECT_LANES" ]; then
  echo "core-boundary: $n_declared lane(s) declared, and this file expects $EXPECT_LANES" >&2
  exit 1
fi

for lane in $LANES; do
  set +e
  sh "$HERE/$lane.sh" > "$run_out" 2>&1
  rc=$?
  set -e
  # A lane's summary always counts what it checked. Its `die` message starts
  # with the same word, so matching the prefix alone would read "could not
  # start" as "failed" -- which is the one distinction this file exists to
  # make, and which it got wrong until the missing-prism case was tried.
  summary=$(grep -E "^$lane: [0-9]+ checked," "$run_out" | tail -1)
  if [ "$rc" -eq 0 ] && [ -n "$summary" ]; then
    printf '  ok       %s\n' "$summary"
    pass=$((pass + 1))
    # A lane that skipped part of itself says what, by name (`  SKIP <why>`);
    # the line is kept, so a reader of this log sees the skip and not only
    # its count in the summary.
    grep -E '^ +SKIP ' "$run_out" | sed "s/^ *SKIP /  SKIP     $lane: /" || true
  elif [ -n "$summary" ]; then
    printf '  FAIL     %s\n' "$summary"
    sed 's/^/           /' "$run_out" | grep -E '^ +(FAIL|.*: )' | head -6
    fail=$((fail + 1))
  else
    # No summary line at all: the lane refused to start. That is the shape a
    # missing tool or a too-old ruby takes, and its own message says which.
    printf '  NOT RUN  %s: %s\n' "$lane" \
      "$(sed "s/^$lane: //" "$run_out" | tr '\n' ' ' | sed 's/  */ /g; s/ $//')"
    notrun=$((notrun + 1))
  fi
done

echo "core-boundary: $EXPECT_LANES lanes, $pass passed, $fail failed, $notrun could not run"
if [ "$fail" -ne 0 ]; then exit 1; fi
if [ "$notrun" -ne 0 ]; then
  if [ "$REQUIRE_ALL" = 1 ]; then
    echo "core-boundary: REQUIRE_ALL is set, so $notrun lane(s) that could not run is a failure" >&2
    exit 1
  fi
  echo "core-boundary: $notrun lane(s) could not run; set REQUIRE_ALL=1 to make that a failure" >&2
fi
