# Synthesis Instructions: examples-watermark-basic-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-watermark-basic-rust.md`

## Example-specific extraction hints
- API focus: `include_bytes!("sample.png")` to embed watermark at compile time, `image::guess_format(buf)`, `image::load_from_memory(buf)`, `image::DynamicImage`, `result.write_to(&mut Cursor::new(&mut out), out_format)`, `rusty_s3` for signed GET from S3; `out_format.to_mime_type()` for response `Content-Type`
- Common patterns: embed watermark PNG via `include_bytes!` (must exist at compile time); fetch source image from S3 using signed GET URL; if body is not a valid image (`guess_format` / `load_from_memory` fail) forward it unchanged; apply alpha-blend watermark via pixel-level loop with `get_pixel` / `put_pixel`; encode result to original format with `write_to`
- Show env var config: `ACCESS_KEY`, `SECRET_KEY`, `REGION`, `BASE_HOSTNAME`, `BUCKET` (S3 credentials), `SCHEME` (optional), `OPACITY` (optional float 0–1.0, default 1.0)
- Gotchas: `include_bytes!` path is relative to `src/lib.rs` and the file must be present at compile time — missing file is a compile error; `OPACITY` must be in `[0.0, 1.0]` — out-of-range returns 500; signed S3 URL expires in 1 hour; non-200 S3 responses are forwarded as-is to the caller; pixel loop clamps watermark dimensions to image bounds; watermark offset is hardcoded to `(0, 0)` in this example
