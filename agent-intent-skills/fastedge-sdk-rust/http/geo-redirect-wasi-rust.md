# Synthesis Instructions: geo-redirect-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/geo-redirect-wasi-rust.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [rust]
capabilities: [geo-redirect, headers]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/geo_redirect
```

## Example-specific extraction hints
- API focus: `req.headers().get("geoip-country-code")`, `env::var(&country_code)`, `Response::builder().status(302).header("location", &url)`
- Show the two-tier lookup: first attempt `env::var(&country_code)` for a country-specific origin, fall back to `BASE_ORIGIN`
- Show that an empty or missing `geoip-country-code` header goes straight to `BASE_ORIGIN` without attempting an env lookup
- No extra dependencies beyond `wstd` + `anyhow` (base skeleton already supplies both)
- "When to Use" hint: user wants to redirect visitors to a country-specific origin URL based on the `geoip-country-code` header injected by FastEdge
