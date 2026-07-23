# Synthesis Instructions: large-dictionary-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/large-dictionary-rust.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [rust]
capabilities: [dictionary, large-config]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/large_env_variable
```

## Example-specific extraction hints
- Extract `fastedge::proxywasm::dictionary::get(name)` — returns `Option<String>`, `unwrap_or_default()` for missing values
- Contrast with `std::env::var()`: dictionary API supports values exceeding the 64KB WASI environment variable limit; for normal-sized env vars (< 64KB), prefer `std::env::var()`
- Show the minimal usage pattern: read large config in `on_http_request_headers`, forward size or content as request headers
- Show logging with `proxy_wasm::hostcalls::log(LogLevel::Info, &msg)`
- CDN pattern: dictionary read in `on_http_request_headers`, no body hooks needed
- "When to Use" hint: user needs to read environment variable values that may exceed the 64KB WASI limit — use the dictionary API for large configuration payloads
