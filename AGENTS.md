# AGENTS.md: synapse-pulse protocol

Development follows [Human-Directed Agentic Engineering (HDAE)](README.md#human-directed-agentic-engineering).
The README defines the human and agent responsibilities and cites Gregory M. Kurtzer's report.

- Run `synapse-pulse run --claims-bin /home/drakestapleton/.local/bin/synapse-claims` (add `--alert` from the
  watch loop). Read findings from stdout or `HOME/pulse/findings.jsonl`; never parse stderr.
- HOME is `--home`, else `$AIEN_COORD_HOME`, else `$HOME/.local/state/aien-coord`; with none, exit 64.
- Ledger access is exec only: `<claims-bin> --home H [--now T] list --all`, `... conflicts`,
  `... expire --agent pulse`. Pulse never writes the ledger itself.
- GitHub access is exec only: `/usr/bin/env HOME=... PATH=... <gh> api -i [-H 'If-None-Match: E'] <path>`,
  no `--paginate`, at most 40 requests per run. Endpoints: `repos/O/R/pulls?state=all&per_page=50` for every
  repo that has an active claim, and `repos/O/R/pulls/N/files?per_page=100` only for open PRs in repos with an
  active path claim that no pr:/branch: claim covers. ETags and bodies are cached in `HOME/pulse/etags/`; a 304
  reuses the cached body. Every request is logged in `HOME/pulse/requests.log` as
  `STAMP PATH inm=ETAG|- status=N bytes=B source=gh|offline|cache`.
- Offline mode `--offline DIR` reads `DIR/<path with / replaced by ,>.http`, the raw `gh api -i` output.
- Session mapping for a claim's `session` value (active claims only):
  1. absolute path to a `.jsonl`: stat it;
  2. 36-char uuid: `<sessions>/<slug>/*_<uuid>.jsonl`;
  3. omp agent id `A.B.C`: `<sessions>/<slug>/<ts>_<uuid>/A/A.B/A.B.C.jsonl` (`X` maps to `X.jsonl`).
  Newest mtime wins. No file: `unknown_session` (info). mtime older than 7200 s: `dead_session`.
- Expired leases are reported exactly once: from the events `expire --agent pulse` prints.
- duplicate_work: intent tokens are lowercase alphanumeric runs of 4+ bytes minus stop words (max 24);
  duplicate when >= 3 shared and 2*shared >= the smaller token count.
- Known gap: a PR-list body over 983040 bytes (json.om source limit) skips that repo with a stderr note.
