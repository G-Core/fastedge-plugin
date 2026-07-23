# Synthesis Instructions: diagnostic-logging-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/diagnostic-logging-wasi-rust.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [rust]
capabilities: [diagnostic-logging, outbound-http]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/diagnostic_logging
```

## Example-specific extraction hints
- API focus: `fastedge::utils::set_user_diag(&str)` — write a single per-request diagnostic tag to the platform log viewer
- Show the three call sites: `set_user_diag("outcome=config_error ...")` on missing config, `set_user_diag(&format!("outcome=origin_unreachable ..."))` on outbound failure, `set_user_diag(&format!("outcome=proxied ..."))` on success
- Show that `set_user_diag` is called synchronously before returning a response — it is not awaited
- Show `logfmt`-style key=value formatting convention (`outcome=<verb> method=... path=... err=...`)
- New dependencies vs base skeleton: `fastedge = "0.4"`
- "When to Use" hint: user wants to attach a structured outcome label to each request so they can filter and search requests in the FastEdge platform log viewer
