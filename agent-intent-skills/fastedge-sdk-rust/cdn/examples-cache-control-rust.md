# Synthesis Instructions: examples-cache-control-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-cache-control-rust.md`

## Example-specific extraction hints
- API focus: `self.get_property(vec!["response.status"])` for status detection (2-byte big-endian u16), `self.get_http_response_header("Content-Type")` for content-type inspection, `self.set_http_response_header("Cache-Control", Some(&value))` for setting cache headers, `self.add_http_response_header("Vary", &value)` for Vary headers
- Show content-type-aware caching tiers:
  - Static assets (image/*, font/*, .js, .css, .wasm): `public, max-age=<STATIC_MAX_AGE>, immutable`
  - HTML: `public, max-age=<HTML_MAX_AGE>, must-revalidate` + `Vary: Accept-Encoding`
  - JSON/XML APIs: `no-cache, no-store, must-revalidate` (when max-age=0) or `private, max-age=<API_MAX_AGE>` + `Vary: Accept, Authorization`
  - Errors (4xx/5xx): `no-store`
  - Default: `public, max-age=600`
- Show `is_static_asset()` helper: check `starts_with("image/")`, `starts_with("font/")`, `contains("application/javascript")`, etc.
- Show env var defaults: `STATIC_MAX_AGE` (31536000), `HTML_MAX_AGE` (3600), `API_MAX_AGE` (0)
- Common patterns: detect status → short-circuit errors to `no-store` → categorize by content-type → set Cache-Control + Vary
- Gotchas: `response.status` is 2-byte big-endian binary (not a string), error responses should never be cached, `Vary` header is critical for shared cache correctness, `immutable` flag prevents revalidation for fingerprinted static assets
