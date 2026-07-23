# Synthesis Instructions: examples-backend-basic-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-backend-basic-rust.md`

## Example-specific extraction hints
- API focus: `fastedge::send_request(req)` for a simple proxied outbound call, `req.into_parts()` to destructure request into `(Parts, Body)`, `querystring::querify(query)` to parse query parameters, `urlencoding::decode()` to URL-decode a parameter value
- Common patterns: extract `url` query param, URL-decode it, build a `GET` request to the decoded URL forwarding the original body, return a summary response (body length + Content-Type)
- Show query param extraction: `uri.query().ok_or(...)`, `querify()`, `.find(|(k,_)| k == &"url")`, `urlencoding::decode()`
- Gotchas: `fastedge::send_request` returns `Result<Response<Body>, fastedge::Error>` — use `.map_err(Error::msg)` to convert; `response.body().len()` reads the full body into memory; only GET method is issued outbound regardless of inbound method; forwarded body from `into_parts` is passed through directly
