#!/bin/sh
# tests/run.sh: build synapse-pulse, then run positive and negative cases in throwaway homes.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
: "${OMEGA_SRC:?set OMEGA_SRC to the pinned omega-mv checkout}"
base=${TEST_BASE:-/tmp/Coord/test-homes}
mkdir -p "$base"
work=$(mktemp -d "$base/pulse-XXXXXX")
bin=$work/synapse-pulse
sh "$here/build.sh" "$OMEGA_SRC" "$bin" || { echo "FAIL build"; exit 1; }
echo "PASS build"
. "$here/tests/cases.sh"
