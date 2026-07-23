# Synthesis Instructions: examples-headers-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-headers-wasi-rust.md`

## Example-specific extraction hints
- API focus: `request.headers()` returns `&HeaderMap`; iteration yields `(&HeaderName, &HeaderValue)` pairs; `name.as_str()` converts `&HeaderName` to `&str`; `Response::builder().header(name, value)` accepts `(&str, &HeaderValue)` directly
- Common patterns: mutable `builder` variable reassigned in a `for` loop to chain headers; `env::var("MY_CUSTOM_ENV_VAR").unwrap_or_default()` for optional env-driven header values; adding the custom header after the copy loop so it appears last and cannot be overridden by request headers
- Gotchas: `HeaderValue` is borrowed from the request for the duration of the loop — do not attempt to move or clone it unless you call `.to_owned()` or `.to_str().unwrap().to_string()`; `Response::builder()` takes ownership at `.body(...)` call so the mutable builder must be finalized last; if a request header value is not valid ASCII, `value.to_str()` returns `Err` — the example passes the raw `&HeaderValue` which avoids this, but note this is only valid when `header()` accepts `HeaderValue` directly
