# Synthesis Instructions: examples-log-time-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-log-time-rust.md`

## Example-specific extraction hints
- API focus: `self.get_current_time()` returns `SystemTime`; `duration_since(SystemTime::UNIX_EPOCH)` converts to elapsed duration; `log::info!` macro for structured logging; `proxy_wasm::set_log_level(LogLevel::Trace)` to configure log verbosity at startup
- Show `get_current_time()` in both request and response hooks: call in `on_http_request_headers` and `on_http_response_headers` to measure timing across both phases
- Show `log` crate usage: `use log::info;` with `log = "0.4"` in Cargo.toml; `proxy_wasm::set_log_level(LogLevel::Trace)` in `proxy_wasm::main!` block to enable log output
- Common patterns: pass `context_id: u32` from `create_http_context` into the struct to correlate per-request log entries; use `as_secs() / 3600` for hour-granularity timestamps in logs
- Gotchas: `get_current_time()` reflects the proxy host's wall clock — it is not a high-resolution performance timer; `duration_since(UNIX_EPOCH).unwrap()` is safe because `get_current_time()` always returns a time after UNIX_EPOCH; `log::info!` output requires `set_log_level` to be set at or below `Info` — `LogLevel::Trace` captures all levels
