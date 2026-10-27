# tests/cases.sh: sourced by tests/run.sh with $bin and $work set. Prints PASS/FAIL per case.
fails=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
NOW=2026-10-27T12:00:00Z
FRESH=202610271159.00   # touch -t: one minute before NOW
STALE=202610270800.00   # four hours before NOW

# fixture CLI: logs its argv, prints canned JSONL per subcommand (child env is empty, so no PATH use)
mkclaims() { # dir
  mkdir -p "$1"
  cat > "$1/claims" <<'EOF'
#!/bin/sh
d=${0%/*}
echo "$*" >> "$d/argv.log"
c=none
for a in "$@"; do case $a in list|conflicts|expire) c=$a ;; esac; done
[ -f "$d/$c.jsonl" ] && while IFS= read -r l; do printf '%s\n' "$l"; done < "$d/$c.jsonl"
[ "$c" = conflicts ] && [ -s "$d/conflicts.jsonl" ] && exit 1
exit 0
EOF
  chmod 755 "$1/claims"
  : > "$1/list.jsonl"
}
# row ID AGENT SESSION KIND TARGET MODE STATE ACTIVE EXPIRES INTENT
row() {
  printf '{"id":"%s","agent":"%s","session":"%s","kind":"%s","target":"%s","mode":"%s","state":"%s","intent":"%s","expires":"%s","active":%s,"since":"2026-10-27T10:00:00Z","last_seq":1,"origin":"agent","evidence":[]}\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" "${11}" "${10}" "$9"
}
http() { # file etag body
  printf 'HTTP/2.0 200 OK\nContent-Type: application/json; charset=utf-8\r\nEtag: %s\r\n\r\n%s' "$2" "$3" > "$1"
}
PULLS='repos,aien-dev,demo,pulls?state=all&per_page=50.http'
FILES7='repos,aien-dev,demo,pulls,7,files?per_page=100.http'
PRS='[{"number":7,"state":"open","merged_at":null,"head":{"ref":"bob-feature"},"title":"feature"},{"number":8,"state":"open","merged_at":null,"head":{"ref":"carol-fix"},"title":"fix"}]'

setup() { # n -> sets t (dir), h (home), s (session file), fx (fixtures)
  t=$work/c$1; h=$t/home; fx=$t/fix; mkdir -p "$h" "$fx" "$t/alert"
  s=$t/sess.jsonl; : > "$s"; touch -t $FRESH "$s"
  mkclaims "$t/cl"
  http "$fx/$PULLS" 'W/"p1"' "$PRS"
  http "$fx/$FILES7" 'W/"f7"' '[{"filename":"src/core/x.om","status":"modified"}]'
}
runp() { # extra args...
  "$bin" --home "$h" run --claims-bin "$t/cl/claims" --now $NOW --sessions "$t/sessions" "$@" > "$t/out" 2> "$t/err"
  rc=$?
}
ALICE() { row aaaaaaaaaaaaaaa1 alice "$s" path 'path:aien-dev/demo:src/**' excl WORKING true 2026-10-27T13:00:00Z 'core rewrite'; }

# 1: open PR 7 touches alice's active path claim, nobody claims the PR -> unclaimed_pr, exit 1
setup 1; ALICE > "$t/cl/list.jsonl"
runp --offline "$fx"
if [ $rc = 1 ] && grep -q '"kind":"unclaimed_pr".*"agent":"alice".*"pr":7,"path":"src/core/x.om"' "$t/out" && cmp -s "$t/out" "$h/pulse/findings.jsonl"
then pass "1 unclaimed_pr rc=$rc"; else fail "1 unclaimed_pr rc=$rc"; cat "$t/out" "$t/err"; fi
# 1n: same, but bob holds pr:aien-dev/demo#7 -> no unclaimed_pr, files endpoint never read
{ ALICE; row bbbbbbbbbbbbbbb2 bob "$s" pr 'pr:aien-dev/demo#7' excl WORKING true 2026-10-27T13:00:00Z 'feature work'; } > "$t/cl/list.jsonl"
rm -rf "$h/pulse"; runp --offline "$fx"
if [ $rc = 0 ] && ! grep -q unclaimed_pr "$t/out" && ! grep -q 'files' "$h/pulse/requests.log"
then pass "1n covered PR is clean rc=$rc"; else fail "1n covered PR rc=$rc"; cat "$t/out" "$t/err"; fi

# 2: carol's pr claim on 8 says MERGED, GitHub says open and unmerged -> status_contradicted
setup 2
row ccccccccccccccc3 carol "$s" pr 'pr:aien-dev/demo#8' excl MERGED true 2026-10-27T13:00:00Z 'fix merged' > "$t/cl/list.jsonl"
runp --offline "$fx"
if [ $rc = 1 ] && grep -q '"kind":"status_contradicted".*"pr":8' "$t/out"
then pass "2 status_contradicted rc=$rc"; else fail "2 status_contradicted rc=$rc"; cat "$t/out" "$t/err"; fi
# 2n: state WORKING on the open PR -> nothing
row ccccccccccccccc3 carol "$s" pr 'pr:aien-dev/demo#8' excl WORKING true 2026-10-27T13:00:00Z 'fix merged' > "$t/cl/list.jsonl"
runp --offline "$fx"
if [ $rc = 0 ] && [ ! -s "$t/out" ]; then pass "2n consistent state rc=$rc"; else fail "2n rc=$rc"; cat "$t/out" "$t/err"; fi

# 3: dave's lease ran out -> pulse execs expire --agent pulse and reports expired_lease
setup 3
row ddddddddddddddd4 dave "$s" repo 'repo:aien-dev/other' excl WORKING false 2026-10-27T11:00:00Z 'old lease' > "$t/cl/list.jsonl"
printf '{"v":1,"seq":9,"ts":"%s","op":"expire","id":"ddddddddddddddd4","agent":"pulse","session":"","kind":"repo","target":"repo:aien-dev/other","mode":"excl","ttl_s":0,"expires":"2026-10-27T11:00:00Z","state":"WORKING","intent":"old lease","evidence":[],"origin":"pulse"}\n' $NOW > "$t/cl/expire.jsonl"
runp --offline "$fx"
if [ $rc = 1 ] && grep -q '"kind":"expired_lease".*"id":"ddddddddddddddd4"' "$t/out" && grep -q -- 'expire --agent pulse' "$t/cl/argv.log"
then pass "3 expired_lease + expire exec rc=$rc"; else fail "3 expired_lease rc=$rc"; cat "$t/out" "$t/err" "$t/cl/argv.log"; fi
# 3n: lease still valid -> no expire exec
row ddddddddddddddd4 dave "$s" repo 'repo:aien-dev/other' excl WORKING true 2026-10-27T13:00:00Z 'old lease' > "$t/cl/list.jsonl"
: > "$t/cl/argv.log"
http "$fx/repos,aien-dev,other,pulls?state=all&per_page=50.http" 'W/"o"' '[]'
runp --offline "$fx"
if [ $rc = 0 ] && ! grep -q expire "$t/cl/argv.log"; then pass "3n no expire exec rc=$rc"; else fail "3n rc=$rc"; cat "$t/cl/argv.log" "$t/err"; fi

# 4: --alert raises exactly one COORD-DRIFT line, keeps other kinds; a clean run resolves it
setup 4; ALICE > "$t/cl/list.jsonl"
printf 'GITHUB-GAP: gap text (since 2026-10-27T00:00:00Z; details x; clear with: aien-watch clear GITHUB-GAP)\n' > "$t/alert/ALERT"
runp --offline "$fx" --alert --alert-dir "$t/alert"
n=$(grep -c '^COORD-DRIFT: ' "$t/alert/ALERT")
if [ $rc = 1 ] && [ "$n" = 1 ] && grep -q '^GITHUB-GAP: ' "$t/alert/ALERT" && grep -q 'clear with: aien-watch clear COORD-DRIFT)$' "$t/alert/ALERT" \
   && grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z COORD-DRIFT 1 coordination finding' "$t/alert/alerts.log"
then pass "4a alert raised once"; else fail "4a alert rc=$rc n=$n"; cat "$t/alert/ALERT" "$t/alert/alerts.log" "$t/err"; fi
runp --offline "$fx" --alert --alert-dir "$t/alert"
n=$(grep -c '^COORD-DRIFT: ' "$t/alert/ALERT")
if [ "$n" = 1 ]; then pass "4b repeat run keeps one line"; else fail "4b n=$n"; cat "$t/alert/ALERT"; fi
{ ALICE; row bbbbbbbbbbbbbbb2 bob "$s" pr 'pr:aien-dev/demo#7' excl WORKING true 2026-10-27T13:00:00Z 'feature work'; } > "$t/cl/list.jsonl"
runp --offline "$fx" --alert --alert-dir "$t/alert"
if [ $rc = 0 ] && ! grep -q '^COORD-DRIFT' "$t/alert/ALERT" && grep -q '^GITHUB-GAP: ' "$t/alert/ALERT" && grep -q ' RESOLVED COORD-DRIFT COORD-DRIFT: ' "$t/alert/alerts.log"
then pass "4c clean run resolves"; else fail "4c rc=$rc"; cat "$t/alert/ALERT" "$t/alert/alerts.log"; fi
rm "$t/alert/ALERT"
runp --offline "$fx" --alert --alert-dir "$t/alert"
if [ ! -e "$t/alert/ALERT" ] && [ "$(grep -c RESOLVED "$t/alert/alerts.log")" = 1 ]; then pass "4d clean run, no alert: no-op"; else fail "4d"; fi

# 5: online through a fake gh: second run sends If-None-Match, gets 304, reuses cached body
setup 5; ALICE > "$t/cl/list.jsonl"
mkdir -p "$t/gh"
cat > "$t/gh/gh" <<'EOF'
#!/bin/sh
d=${0%/*}
echo "HOME=$HOME PATH=$PATH $*" >> "$d/argv.log"
inm=0; for a in "$@"; do case $a in If-None-Match:*) inm=1 ;; esac; p=$a; done
f=$d/fix/$(printf '%s' "$p" | tr / ,).http
if [ $inm = 1 ]; then printf 'HTTP/2.0 304 Not Modified\nEtag: W/"x"\r\n\r\n'; echo 'gh: HTTP 304' >&2; exit 1; fi
[ -f "$f" ] || { echo "gh: HTTP 404" >&2; exit 1; }
while IFS= read -r l || [ -n "$l" ]; do printf '%s\n' "$l"; done < "$f"
EOF
chmod 755 "$t/gh/gh"; cp -r "$fx" "$t/gh/fix"
runp --gh "$t/gh/gh"; rc1=$rc; cp "$t/out" "$t/out1"
runp --gh "$t/gh/gh"
if [ $rc1 = 1 ] && [ $rc = 1 ] && cmp -s "$t/out1" "$t/out" && grep -q 'status=304 .*source=cache' "$h/pulse/requests.log" \
   && grep -q "If-None-Match: W/\"p1\" repos/aien-dev/demo/pulls" "$t/gh/argv.log" && grep -q '^HOME=/home/drakestapleton PATH=/home/drakestapleton/.local/bin:/usr/bin:/bin api -i' "$t/gh/argv.log"
then pass "5 304 reuses cache"; else fail "5 304 rc1=$rc1 rc=$rc"; cat "$h/pulse/requests.log" "$t/gh/argv.log" "$t/err"; fi

# 6: sessions: stale session file -> dead_session; unknown uuid -> unknown_session (info only, exit 0)
setup 6; touch -t $STALE "$s"
row eeeeeeeeeeeeeee5 erin "$s" repo 'repo:aien-dev/other' excl WORKING true 2026-10-27T13:00:00Z 'erin work' > "$t/cl/list.jsonl"
http "$fx/repos,aien-dev,other,pulls?state=all&per_page=50.http" 'W/"o"' '[]'
runp --offline "$fx"
if [ $rc = 1 ] && grep -q '"kind":"dead_session","severity":"warn"' "$t/out"; then pass "6a dead_session"; else fail "6a rc=$rc"; cat "$t/out" "$t/err"; fi
row eeeeeeeeeeeeeee5 erin 01234567-89ab-cdef-0123-456789abcdef repo 'repo:aien-dev/other' excl WORKING true 2026-10-27T13:00:00Z 'erin work' > "$t/cl/list.jsonl"
runp --offline "$fx"
if [ $rc = 0 ] && grep -q '"kind":"unknown_session","severity":"info"' "$t/out"; then pass "6b unknown_session info rc=0"; else fail "6b rc=$rc"; cat "$t/out" "$t/err"; fi

# 7: usage and malformed input
setup 7
env -i "$bin" run --claims-bin "$t/cl/claims" > /dev/null 2>&1; rc=$?
if [ $rc = 64 ]; then pass "7a no home -> 64"; else fail "7a rc=$rc"; fi
"$bin" --home "$h" run > /dev/null 2>&1; rc=$?
if [ $rc = 64 ]; then pass "7b no --claims-bin -> 64"; else fail "7b rc=$rc"; fi
"$bin" --home "$h" run --claims-bin "$t/cl/claims" --now yesterday > /dev/null 2>&1; rc=$?
if [ $rc = 64 ]; then pass "7c bad --now -> 64"; else fail "7c rc=$rc"; fi
echo 'not json' > "$t/cl/list.jsonl"
runp --offline "$fx"
if [ $rc = 65 ]; then pass "7d malformed claims output -> 65"; else fail "7d rc=$rc"; cat "$t/err"; fi

echo "failures: $fails"
[ $fails = 0 ]
