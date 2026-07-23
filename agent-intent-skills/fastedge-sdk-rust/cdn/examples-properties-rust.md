# Synthesis Instructions: examples-properties-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-properties-rust.md`

## Example-specific extraction hints
- API focus: `self.get_property(vec![path])` returning `Option<Vec<u8>>` — decode with `String::from_utf8_lossy()`; `self.set_property(vec![path], Some(bytes))` for writing
- Document all available request property paths: `request.url`, `request.host`, `request.path`, `request.scheme`, `request.extension`, `request.query`, `request.x_real_ip`, `request.country`, `request.city`, `request.asn`, `request.geo.lat`, `request.geo.long`, `request.region`, `request.continent`, `request.country.name`
- Note `response.status` is 2-byte big-endian `u16` (NOT a string) — decode with `u16::from_be_bytes([bytes[0], bytes[1]])`
- Common patterns: read geo properties for routing decisions, set `request.url`/`request.path`/`request.host` to rewrite requests
- Show `self.add_http_response_header_bytes()` for forwarding raw property values as headers
- Gotchas: all properties return raw `Vec<u8>` — most are plain UTF-8 strings (decode with `.and_then(|b| String::from_utf8(b).ok()).unwrap_or_default()`), but `response.status` is a 2-byte big-endian `u16` (decode with `u16::from_be_bytes`, NOT `String::from_utf8`), some properties may not be available depending on request phase
