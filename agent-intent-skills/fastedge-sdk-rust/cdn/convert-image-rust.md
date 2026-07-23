# Synthesis Instructions: convert-image-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/convert-image-rust.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [rust]
capabilities: [image-conversion, response-body-transformation, content-negotiation]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/convert_image
```

## Example-specific extraction hints
- Extract three-hook pipeline: `on_http_request_headers` sets an `Image-Format` request header to flag which format to produce and rewrites it for cache keying; `on_http_response_headers` checks the flag and sets response headers (`Vary`, `Content-Type`, `Transfer-Encoding`) and stores the target content-type in `response.content-type` property; `on_http_response_body` reads that property, decodes the full body, converts with `image` crate, and writes the transformed bytes back
- Show cross-hook signalling via `self.set_property` / `self.get_property`: request hook signals intent through the `Image-Format` request header; response-headers hook propagates format into `response.content-type` property for the body hook
- Show env var configuration: `FORMATS_TO_TRANSFORM` (comma-separated extensions), `IGNORED_UA_LIST` (comma-separated UA substrings to skip), `AVIF_SPEED` (1–10, default 5), `AVIF_QUALITY` (1–100, default 70)
- Show `request.extension` property usage to extract the file extension without manual path splitting; note safe decoding chain for `Option<Vec<u8>>` from `get_property`
- Show `response.status` decoding: `get_property(vec!["response.status"])` returns a 2-byte big-endian `u16` — document the `u16::from_be_bytes([status[0], status[1]])` pattern and the length check
- Show body buffering: return `Action::Pause` when `!end_of_stream` to accumulate the complete body before processing; use `self.get_http_response_body(0, body_size)` to retrieve it
- Show `Vary: Image-Format` response header addition so CDN caches original and converted responses separately
- "When to Use" hint: user wants to transcode images (e.g., to AVIF) at the CDN edge based on request file extension and User-Agent, avoiding re-encoding cached originals
