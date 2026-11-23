#!/bin/sh
# SubsetRefusals.cpp and SubsetTables.cpp against
# their pin; no build.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "${RUBY:-ruby}" "$HERE/check.rb"
