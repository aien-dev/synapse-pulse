#!/bin/sh
# build.sh OMEGA_SRC OUT: compile synapse-pulse with the pinned seeded Omega compiler.
# Refuses to build unless OMEGA_SRC is at the omega.pin commit and its omc matches the pinned sha256.
set -eu
[ $# -eq 2 ] || { echo "usage: build.sh OMEGA_SRC OUT" >&2; exit 64; }
src=$1 out=$2
here=$(cd "$(dirname "$0")" && pwd)
want_rev=$(sed -n '1s/^aien-dev\/omega-mv@//p' "$here/omega.pin")
want_omc=$(sed -n '2s/^omc-sha256 //p' "$here/omega.pin")
omc=$src/seed/out/omc
have_rev=$(git -C "$src" rev-parse HEAD)
[ "$have_rev" = "$want_rev" ] || { echo "build.sh: omega-mv is $have_rev, omega.pin wants $want_rev" >&2; exit 65; }
[ -x "$omc" ] || { echo "build.sh: $omc missing (build it with seed/omc/build.sh in omega-mv)" >&2; exit 65; }
have_omc=$(sha256sum "$omc" | cut -d' ' -f1)
[ "$have_omc" = "$want_omc" ] || { echo "build.sh: omc sha256 $have_omc, omega.pin wants $want_omc" >&2; exit 65; }
{ printf 'om2\n'; cat "$src/seed/json/json.om" "$here"/src/*.om; } > "$out.unit.om"
rm -f "$out"
if ! "$omc" < "$out.unit.om" > "$out.tmp" 2> "$out.err"; then
  cat "$out.err" >&2; rm -f "$out.tmp"; exit 70
fi
if [ -s "$out.err" ]; then cat "$out.err" >&2; rm -f "$out.tmp"; exit 70; fi
chmod 755 "$out.tmp" && mv "$out.tmp" "$out"
echo "built $out" >&2
