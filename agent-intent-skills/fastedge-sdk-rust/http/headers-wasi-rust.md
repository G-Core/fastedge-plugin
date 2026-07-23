# Synthesis Instructions: headers-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/headers-wasi-rust.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [rust]
capabilities: [headers, env-vars]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/headers
```

## Example-specific extraction hints
- API focus: `request.headers()` iteration, `Response::builder().header(name.as_str(), value)` chaining in a loop, `env::var("MY_CUSTOM_ENV_VAR").unwrap_or_default()`
- Show the mutable-builder pattern: `let mut builder = Response::builder().status(200)` then `builder = builder.header(...)` inside a loop
- Show copying all incoming request headers onto the response builder before adding an extra custom header from an env var
- No extra dependencies beyond `wstd` + `anyhow` (base skeleton already supplies both)
- "When to Use" hint: user wants to inspect, copy, or inject HTTP headers — echoing request headers, adding custom response headers from environment variables
