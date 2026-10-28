Part of [aien-dev/synapse](https://github.com/aien-dev/synapse) (pinned in `synapse.pin`).

# synapse-pulse

`synapse-pulse` reconciles the agent claims ledger against GitHub pull requests and live omp
sessions and reports drift as JSONL findings. It is written in seeded Omega (`src/*.om`), compiled by the
compiler pinned in `omega.pin`. There is no INTERIM host code in the product; `tests/` holds shell test
harness and fixtures only.

```
synapse-pulse [--home DIR] run [--alert] [--alert-dir DIR] [--gh PATH] [--sessions DIR]
              --claims-bin PATH [--offline FIXTUREDIR] [--now 2026-10-27T00:00:00Z]
```

Findings go to stdout and atomically to `HOME/pulse/findings.jsonl`, one object per line with keys in this
order: `kind,severity,repo,target,id,agent,session,pr,path,other_id,other_agent,detail`.

| kind | severity | meaning |
|---|---|---|
| conflict | error | two active exclusive claims overlap (from `synapse-claims conflicts`) |
| expired_lease | warn | lease expired; pulse ran `synapse-claims expire --agent pulse` |
| dead_session | warn | the claim's omp session file has not changed for 2 h |
| unknown_session | info | no session file found for the claim's session |
| unclaimed_pr | warn | open PR touches files under another agent's active path claim, no pr/branch claim covers it |
| status_contradicted | warn | claim state disagrees with GitHub (MERGED but not merged, active claim on a closed PR) |
| duplicate_work | warn | two agents' active claims have strongly overlapping intent |

Exit: 0 clean (info only), 1 warn/error findings, 64 usage, 65 malformed claims output, 70 internal,
75 GitHub errors and nothing found. `--alert` raises or resolves `COORD-DRIFT` in the aien-watch
`ALERT`/`alerts.log` format.

Build: `./build.sh /path/to/omega-mv out/synapse-pulse`. Test: `OMEGA_SRC=/path/to/omega-mv sh tests/run.sh`.

## Connected repos
- Parent: [aien-dev/synapse](https://github.com/aien-dev/synapse) (pinned in `synapse.pin`)
- [aien-dev/synapse-claims](https://github.com/aien-dev/synapse-claims): claims ledger CLI (pulse execs it)
- [aien-dev/synapse-map](https://github.com/aien-dev/synapse-map): repository map
- [aien-dev/synapse-pulse](https://github.com/aien-dev/synapse-pulse): this reconciler
- [aien-dev/synapse-mcp](https://github.com/aien-dev/synapse-mcp): MCP server exposing the tools
- [aien-dev/synapse-board](https://github.com/aien-dev/synapse-board): generated board views and BOARD.md migration

## Human-Directed Agentic Engineering

Development follows Human-Directed Agentic Engineering (HDAE): humans define goals, architecture,
constraints, acceptance criteria, and stopping points; agents implement, execute checks, diagnose
failures, and revise within those boundaries. Human review retains responsibility for claims,
acceptance, and release decisions.

For the documented method and a systems-software case study, see Gregory M. Kurtzer,
[*Ginux: Building an Independent Kernel That Runs Linux Userspace through Human-Directed Agentic
Engineering* (2026)](https://doi.org/10.5281/zenodo.23682548).
