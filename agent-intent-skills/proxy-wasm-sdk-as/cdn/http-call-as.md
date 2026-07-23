# Synthesis Instructions: http-call-as.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/http-call-as.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [assemblyscript]
capabilities: [http-call, async-dispatch, outbound]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/httpCall
```

## Example-specific extraction hints
- Extract `(this.root_context as <RootType>).httpCall(upstream, headers, body, trailers, timeoutMs, ctx, callback)` — dispatched from the root context, not the stream context; returns a `WasmResultValues` status
- Show pseudo-header construction via `makeHeaderPair(":scheme", ...)`, `":authority"`, `":path"`, `":method"` plus optional custom headers — push to an `Array<HeaderPair>`
- Show the async callback signature `(ctx: BaseContext, hdrs: u32, bodySize: usize, trls: u32) => void` and reading the response body with `get_buffer_bytes(BufferTypeValues.HttpCallResponseBody, 0, bodySize as u32)`
- Show response-header access via `stream_context.headers.http_callback.get(name)` inside the callback
- Show the re-dispatch latch pattern: instance `bool` field (`httpCallDispatched`) — first invocation returns `FilterHeadersStatusValues.StopIteration`, FastEdge re-enters `onRequestHeaders` after the callback and the latch makes the second call return `Continue`
- Show error handling: when `result != WasmResultValues.Ok` return a 500 via `send_http_response`; when `hdrs == 0` inside the callback log an error
- "When to Use" hint: user wants to make async outbound HTTP calls to external services from a CDN filter at the CDN layer
