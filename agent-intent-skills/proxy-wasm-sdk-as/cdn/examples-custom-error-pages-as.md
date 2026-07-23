# Synthesis Instructions: examples-custom-error-pages-as.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-custom-error-pages-as.md`

## Example-specific extraction hints
- API focus: `get_property("response.status")` returns 2-byte big-endian `ArrayBuffer` (NOT UTF-8 — decode via `Uint8Array.wrap(buf)` and `(u32(bytes[0]) << 8) | u32(bytes[1])`); `stream_context.headers.response.replace/remove`; `set_buffer_bytes(BufferTypeValues.HttpResponseBody, 0, body_buffer_length as u32, encoded)`; `FilterDataStatusValues.StopIterationAndBuffer`
- Show the two-hook flow: `onResponseHeaders` detects 4xx/5xx and rewrites Content-Type/Transfer-Encoding/Content-Length; `onResponseBody` buffers until `end_of_stream` then replaces the body with branded HTML
- Show `set_buffer_bytes` length argument: pass `body_buffer_length` (the original buffer length) — otherwise original bytes beyond the new body's length remain at the tail of the response
- Gotchas: response status is a binary `u16`, not a string — must NOT decode with `String.UTF8.decode`; `remove("Content-Length")` is the FastEdge CDN platform's empty-string-set behavior (not nginx's), so downstream code testing for header absence must test for both missing and empty; instance state does not survive between header and body hooks — re-read the status from the property in `onResponseBody`; no closures in AssemblyScript — status→string lookups must be class private methods
