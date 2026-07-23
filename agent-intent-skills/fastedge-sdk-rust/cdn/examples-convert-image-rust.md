# Synthesis Instructions: examples-convert-image-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-convert-image-rust.md`

## Example-specific extraction hints
- API focus: `self.get_property(vec!["request.extension"])` for file extension; `self.get_property(vec!["response.status"])` decoded as 2-byte big-endian `u16`; `self.set_property(vec!["response.content-type"], Some(bytes))` for cross-hook signalling; `self.get_http_response_body(0, body_size)` to retrieve the full buffered body; `self.set_http_response_body(0, body_size, &out)` to replace it
- Show response-body buffering pattern: return `Action::Pause` in `on_http_response_body` while `!end_of_stream`; only process when `end_of_stream == true` and body is complete
- Show three-hook pipeline: request headers → flag and cache-key via `Image-Format` header; response headers → check status, set `Vary`, update `Content-Type`/`Transfer-Encoding`, store target format in `response.content-type` property; response body → decode property, load image, encode to AVIF, write back
- Show `response.status` decoding: property returns `Option<Vec<u8>>`; expect exactly 2 bytes; decode with `u16::from_be_bytes([b[0], b[1]])` (big-endian)
- Common patterns: env-var helpers with range clamping (`u8_param`), `request.extension` for format detection, `Vary` header for cache differentiation, `Content-Length: None` + `Transfer-Encoding: Chunked` before body replacement
- Gotchas: `Content-Length` must be cleared (set to `None`) before replacing response body — FastEdge platform sets it to empty string, not removes it; body hook must not call `send_http_response` after partial processing or the connection may be broken; `image` crate AVIF encoding is CPU-intensive — choose `AVIF_SPEED` carefully; `request.extension` returns `None` for paths with no extension, not an empty string
