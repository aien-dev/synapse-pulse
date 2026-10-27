#!/bin/sh
# tests/diag.sh OMEGA_SRC LIBS...: test harness, not product. omc stops at the first refusal, so this
# compiles one unit per function: that function in full, every other function reduced to its signature
# and a trivial body. Prints one line per refused function with omc's `om2 diag` record.
set -u
src=$1; shift
omc=$src/seed/out/omc
here=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
cat "$here"/src/*.om > "$tmp/all.om"
nf=$(grep -c '^fn ' "$tmp/all.om")
bad=0
k=1
while [ $k -le "$nf" ]; do
  awk -v keep=$k '
    function stub(sig,   t) {
      t = sig; sub(/.* to /, "", t)
      print sig
      if (t == "bool") print "ret false"
      else if (t != "void") print "ret " t " 0"
      print "end"
    }
    /^fn / { n++; infn = 1; d = 1; full = (n == keep); if (full) print; else stub($0); next }
    infn {
      if ($0 ~ /^(if|for|while) /) d++
      else if ($0 == "end") d--
      if (full) print
      if (d == 0) infn = 0
      next
    }
    { print }
  ' "$tmp/all.om" > "$tmp/body.om"
  name=$(grep '^fn ' "$tmp/all.om" | sed -n "${k}p" | cut -d' ' -f2)
  { printf 'om2 diag\n'; for l in "$@"; do cat "$src/$l"; done; cat "$tmp/body.om"; } > "$tmp/u.om"
  if ! "$omc" < "$tmp/u.om" > /dev/null 2> "$tmp/err" || [ -s "$tmp/err" ]; then
    ln=$(sed -n 's/^omc: line \([0-9]*\).*/\1/p' "$tmp/err" | head -1)
    echo "REFUSED $name: $(tr '\n' ' ' < "$tmp/err") src: $(sed -n "${ln:-1}p" "$tmp/u.om" | cut -c1-120)"
    bad=$((bad + 1))
  fi
  k=$((k + 1))
done
echo "diag: $nf functions, $bad refused"
rm -rf "$tmp"
[ $bad = 0 ]
