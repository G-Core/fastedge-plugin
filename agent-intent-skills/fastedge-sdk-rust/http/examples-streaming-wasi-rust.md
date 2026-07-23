# Synthesis Instructions: examples-streaming-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-streaming-wasi-rust.md`

## Example-specific extraction hints
- API focus: `wstd::http::body::Body::from_stream(stream)` — stream item type must be `String`; `futures_lite::stream::unfold(initial_state, async_closure)` — returns `None` to terminate, `Some((item, next_state))` to emit; `wstd::time::Timer::after(Duration).wait().await` for async sleep between chunks
- Common patterns: use `stream::unfold` with a counter as state to emit a fixed number of chunks; insert `Timer::after` inside the closure to introduce delay; pass the stream directly to `Body::from_stream` without collecting
- Gotchas: `futures-lite` must be added to Cargo.toml; stream item type is `String` (not `Bytes` or `&str`) — format chunks with `format!()`; client-side buffering (e.g. curl without `-N`) may hide the streaming effect; do not collect the stream before passing to `Body::from_stream` — that defeats the purpose; `Timer::after` is async-only, only usable inside `async` blocks
