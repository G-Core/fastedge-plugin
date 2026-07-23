# Synthesis Instructions: examples-large-dictionary-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-large-dictionary-rust.md`

## Example-specific extraction hints
- API focus: `fastedge::proxywasm::dictionary::get(name)` returning `Option<String>` (not `Vec<u8>` like `secret::get`), `unwrap_or_default()` for missing values
- Contrast `dictionary::get` vs `std::env::var`: dictionary API supports values exceeding 64KB WASI env var limit; for normal-sized values (< 64KB), prefer `std::env::var()`
- Common patterns: read large configuration in `on_http_request_headers`, log size, forward as header metadata to upstream
- Show logging: `proxy_wasm::hostcalls::log(LogLevel::Info, &msg)` with `.ok()` to ignore log errors
- Gotchas: dictionary API returns `Option<String>` (not `Result<Option<Vec<u8>>, u32>` like `secret::get`), `unwrap_or_default()` returns empty string for missing values (no error), only use dictionary API when values may exceed 64KB — `std::env::var()` is simpler for normal config
