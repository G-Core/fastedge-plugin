# Synthesis Instructions: ab-testing-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/ab-testing-wasi-rust.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [rust]
capabilities: [ab-testing, cookies, outbound-http]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/ab_testing
```

## Example-specific extraction hints
- API focus: `wstd::http::Client::new().send()`, `Request::get()`, `Response::builder()`, cookie header manipulation
- Show the static `TESTS` / `VariantWeight` / `AbTest` struct pattern for declaring weighted variants at compile time
- Show `extract_abid` + `strip_abid` cookie helpers (read, clean, and re-set the `x-fastedge-abid` cookie)
- Show `assign_variant` weighted bucket logic (deterministic assignment from a `0.NNNN` float XID)
- Show how `ab-test-<name>` headers are forwarded to the origin and `set-cookie` is applied on the response
- No extra dependencies beyond `wstd` + `anyhow` (base skeleton already supplies both)
- "When to Use" hint: user wants to split traffic between variants using a cookie-persisted A/B id and forward variant assignments to an upstream origin
