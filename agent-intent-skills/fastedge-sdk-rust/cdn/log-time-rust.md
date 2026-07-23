# Synthesis Instructions: log-time-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/log-time-rust.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [rust]
capabilities: [logging, timing, observability]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/log_time
```

## Example-specific extraction hints
- Extract `self.get_current_time()` usage in both `on_http_request_headers` and `on_http_response_headers` to log the current time in hours since UNIX epoch
- Show `log::info!` macro usage with `proxy_wasm::set_log_level(LogLevel::Trace)` in `proxy_wasm::main!` — this is the recommended structured logging approach for CDN apps, in contrast to `println!` used in simpler examples
- Show struct field `context_id: u32` passed through `create_http_context` to correlate log entries for the same request across hooks
- Show `duration_since(SystemTime::UNIX_EPOCH).unwrap().as_secs() / 3600` as the time-to-hours computation
- "When to Use" hint: user wants to add timing or observability logging to request and response phases of a CDN app, or needs a minimal example demonstrating `get_current_time()` and structured logging with the `log` crate
