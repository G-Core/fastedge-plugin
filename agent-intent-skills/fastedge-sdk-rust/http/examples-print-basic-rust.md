# Synthesis Instructions: examples-print-basic-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-print-basic-rust.md`

## Example-specific extraction hints
- API focus: `req.method().as_str()`, `req.uri().to_string()`, `req.headers()` iterator yielding `(HeaderName, HeaderValue)`, `header_value.to_str()` returning `Result` (non-UTF-8 values possible)
- Common patterns: iterate all request headers with `for (h, v) in req.headers()`; accumulate into a `String` with `push_str`; handle non-UTF-8 header values gracefully with a `"not a valid text"` fallback; return the full request reflection as a plain-text body
- Gotchas: `header.as_str()` on `HeaderName` is always valid UTF-8; `HeaderValue.to_str()` can fail for binary header values — always handle the `Err` branch; `req.uri().to_string()` may include scheme/host depending on incoming request format; no outbound calls — pure request inspection
