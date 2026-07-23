# Synthesis Instructions: examples-diagnostic-logging-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-diagnostic-logging-wasi-rust.md`

## Example-specific extraction hints
- API focus: `fastedge::utils::set_user_diag(tag: &str)` — no return value, no await; the tag appears in the platform's per-request log viewer and is distinct from stdout `println!` output
- Common patterns: call `set_user_diag` at every terminal branch (config error, upstream failure, success) before returning the response; use `logfmt`-style `key=value` strings so the tag is parseable by log tooling; include `method`, `path`, and `status` in success tags for correlation
- Gotchas: `set_user_diag` is for short filterable outcome labels — it is NOT a substitute for `println!` verbose tracing (those go to stdout and are independent); only the last call per request is visible in the platform viewer — do not call it multiple times expecting concatenation; the tag string has a platform-defined length limit (keep it under 256 chars to be safe)
