# Synthesis Instructions: examples-geo-redirect-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-geo-redirect-rust.md`

## Example-specific extraction hints
- API focus: `self.get_property(vec!["request.country"])` for geo detection, `self.set_property(vec!["request.url"], Some(bytes))` for origin rewriting, `std::env::var()` for origin mapping
- Show country-based origin selection: env var per country code (e.g., `US`, `DE`), `DEFAULT` as fallback
- Common patterns: detect country → look up origin URL from env → read and preserve request path → construct new URL → set `request.url` property
- Contrast with geoblock: geo-redirect routes to different origins, geoblock rejects entirely
- Show Host header preservation with `self.set_http_request_header("Host", Some(&host))`
- Gotchas: `get_property` returns `Option<Vec<u8>>` — decode with `.and_then(|b| String::from_utf8(b).ok()).unwrap_or_default()` to avoid panics on invalid UTF-8, country code may be empty (handle gracefully), origin URL should have trailing slash stripped
