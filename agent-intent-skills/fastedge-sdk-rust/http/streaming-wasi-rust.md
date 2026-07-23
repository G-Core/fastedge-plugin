# Synthesis Instructions: streaming-wasi-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/streaming-wasi-rust.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [rust]
capabilities: [streaming-response]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/streaming
```

## Example-specific extraction hints
- API focus: `Body::from_stream(stream)` accepts any `futures_lite::Stream<Item = String>`; `futures_lite::stream::unfold(state, async_fn)` for building a lazy stateful stream; `wstd::time::{Duration, Timer}` for async delays between chunks
- Show the unfold pattern: initial state is `0u32`, closure returns `None` to terminate or `Some((chunk_string, next_state))` to emit a chunk and advance
- `futures-lite` must be added to Cargo.toml (not in base skeleton)
- "When to Use" hint: user wants to send a response body as a stream of chunks produced over time, rather than buffering the full body in memory before responding
