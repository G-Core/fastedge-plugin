# Synthesis Instructions: examples-api-key-as.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-api-key-as.md`

## Example-specific extraction hints
- API focus: `getSecret("API_KEY")` (returns `string`, empty for not-found, never null), `stream_context.headers.request.get("X-API-Key")`, `send_http_response(status, msg, body, headers)`, `makeHeaderPair(name, value)`, `stream_context.headers.request.remove(name)`
- Show the validation flow in `onRequestHeaders`: missing secret → 500, missing client header → 401 with `WWW-Authenticate: API-Key`, mismatched value → 403, success → `FilterHeadersStatusValues.Continue`
- Show header stripping before forward: `stream_context.headers.request.remove("X-API-Key")`
- Gotchas: empty-string (not null) check on `getSecret`; `remove` is the FastEdge CDN platform's empty-string-set behavior — upstream sees `X-API-Key:` (empty) rather than a missing header (when downstream code tests absence it must check for both missing and empty); no try/catch in AssemblyScript — every branch must explicitly return `StopIteration` after `send_http_response`
