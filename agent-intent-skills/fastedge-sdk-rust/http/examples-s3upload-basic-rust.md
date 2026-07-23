# Synthesis Instructions: examples-s3upload-basic-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-s3upload-basic-rust.md`

## Example-specific extraction hints
- API focus: `rusty_s3::{Bucket, Credentials, S3Action, UrlStyle}`, `Bucket::new(url, UrlStyle::Path, bucket, region)`, `bucket.put_object(Some(&creds), fname)`, `action.sign(Duration::from_secs(3600))` — produces a pre-signed PUT URL; `fastedge::send_request` to execute the signed PUT
- Common patterns: accept `POST` or `PUT` request; extract `name` query param for S3 object key; read `Content-Type` header (fallback `"application/octet-stream"`); enforce optional `MAX_FILE_SIZE` limit; build signed URL via `prepare_s3(fname)` → send PUT to S3; strip query string from signed URL before returning it to caller
- Show env var config: `ACCESS_KEY`, `SECRET_KEY`, `REGION`, `BASE_HOSTNAME`, `BUCKET` (all required), `SCHEME` (optional, default `"http"`), `MAX_FILE_SIZE` (optional, bytes limit)
- Gotchas: `req.into_body()` consumes the request — extract all needed parts (method, headers, query) before calling it; signed URL expires in 1 hour; `OPTIONS` method returns `204 NO_CONTENT` for CORS preflight; `Content-Length` must be set explicitly on the outbound PUT request; on S3 200, response body is replaced with the clean object URL (query stripped)
