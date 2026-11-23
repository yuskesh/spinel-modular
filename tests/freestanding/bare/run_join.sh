#!/usr/bin/env bash
# bare against ints: one kernel, two platforms of this repository. After
# run_gates.sh here and ints's build_all.sh and run_gates.sh in the same
# $FS_WORK (run.sh runs ints first). This is not an oracle: both sides are the
# same compiler's object, run on the same QEMU machine, with and without Zephyr.
#
# Writes $RES/platforms.tsv:
#   same_kernel_object  bare's kern.o and ints's kern.cortex-m33-zephyr.o are
#                       byte-identical (the profiles differ only in platform);
#   rows_match_zephyr   every case line, BEGIN and END aside, is the same.
set -uo pipefail
HERE=$(cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/../lane-env.sh"
INTS_OUT=${FS_WORK:-${TMPDIR:-/tmp}/spinel-freestanding}/ints
zlog="$INTS_OUT/results/qemu_m33.log"
zobj="$INTS_OUT/gen/kern.cortex-m33-zephyr.o"
for f in "$zlog" "$zobj" "$RES/qemu_bm.log" "$OUT/gen/kern.o"; do
  [ -f "$f" ] || { echo "$LANE: no $f (run ints and this lane's run_gates.sh first)" >&2; exit 2; }
done

extract() {  # $1 = log -> case<TAB>result
  grep '^INTS	' "$1" | grep -v '	BEGIN	\|	END	\|	FATAL	' | cut -f2- | tr -d '\r'
}
extract "$zlog" > "$RES/rows.zephyr.tsv"
extract "$RES/qemu_bm.log" > "$RES/rows.baremetal.tsv"
{
printf 'check\tdetail\tverdict\n'
if cmp -s "$OUT/gen/kern.o" "$zobj"; then v=PASS; d=identical; else v=FAIL; d=differ; fi
printf 'same_kernel_object\t%s\t%s\n' "$d" "$v"
n=$(wc -l < "$RES/rows.baremetal.tsv" | tr -d ' ')
if [ "$n" -gt 0 ] && cmp -s "$RES/rows.zephyr.tsv" "$RES/rows.baremetal.tsv"; then
  v=PASS; d="$n rows"
else
  v=FAIL; d="$(diff "$RES/rows.zephyr.tsv" "$RES/rows.baremetal.tsv" | grep -c '^[<>]') differing lines"
fi
printf 'rows_match_zephyr\t%s\t%s\n' "$d" "$v"
} > "$RES/platforms.tsv"
cat "$RES/platforms.tsv"
! grep -q FAIL "$RES/platforms.tsv"
