# Synthesis Instructions: custom-error-pages-as.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/custom-error-pages-as.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [assemblyscript]
capabilities: [error-pages, response-body]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/customErrorPages
```

## Example-specific extraction hints
- Extract response-status decoding: `get_property("response.status")` returns a **2-byte big-endian** `ArrayBuffer` — wrap with `Uint8Array.wrap(buf)` and combine as `(u32(bytes[0]) << 8) | u32(bytes[1])`. This is NOT a UTF-8 string.
- Show header prep in `onResponseHeaders` when `code >= 400 && code < 600`: `stream_context.headers.response.replace("Content-Type", "text/html")`, `remove("Content-Length")`, `replace("Transfer-Encoding", "Chunked")`. Note `remove` is the FastEdge CDN platform's empty-string-set behavior, not a true delete
- Show body replacement in `onResponseBody`: buffer with `FilterDataStatusValues.StopIterationAndBuffer` until `end_of_stream`, then build the HTML string and call `set_buffer_bytes(BufferTypeValues.HttpResponseBody, 0, body_buffer_length as u32, String.UTF8.encode(html))` — replace using `body_buffer_length` (not the new body's `byteLength`), otherwise original bytes survive at the tail
- Show status→title/description lookup as class **private methods** (no closures, no default args on nested functions): `getErrorTitle(code)`, `getErrorDescription(code)`
- Show that the response status must be re-read from the property in `onResponseBody` — instance state from `onResponseHeaders` does not survive the hop
- No new dependencies beyond the base skeleton
- "When to Use" hint: user wants to replace default 4xx/5xx upstream responses with a custom branded HTML error page at the CDN layer
