# Extension proposals

synapse-pulse has no INTERIM host implementation. Gaps found while writing it:

1. json.om source limit 983040 bytes: a 50-PR GitHub list is about 875 KB. A streaming tokenizer
   (`js_parse` over a window with resumable state) would remove the per-repo skip.
2. No shared library mechanism across repos: `src/00base.om` is copied into synapse-mcp. A pinned
   `seed/lib` unit for process spawning (fork/memfd/waitpid with timeout) would remove the copy.
