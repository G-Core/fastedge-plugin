# Synthesis Instructions: examples-geo-redirect-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-geo-redirect-wasi-rust.md`

## Example-specific extraction hints
- API focus: `req.headers().get("geoip-country-code").and_then(|v| v.to_str().ok()).unwrap_or("")` for header extraction; `env::var(&country_code).unwrap_or(base_origin)` for per-country URL lookup; `Response::builder().status(302).header("location", &redirect_origin).body(Body::empty())` for the redirect response
- Common patterns: read `BASE_ORIGIN` from env (hard error if missing); read the country code from the FastEdge-injected header; attempt a country-specific env var by the country code string as the key; fall back to `BASE_ORIGIN` when the env var is absent
- Gotchas: `geoip-country-code` is a FastEdge platform-injected header — it is not present in local test requests unless the test fixture sets it explicitly; per-country env vars use the ISO 3166-1 alpha-2 code as the variable name (e.g. `US`, `DE`, `GB`), which means they collide with any other two-letter env vars; `BASE_ORIGIN` must be set or the handler returns 500 immediately
