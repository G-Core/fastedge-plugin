# Synthesis Instructions: api-key-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/api-key-rust.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [rust]
capabilities: [auth, api-key]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/api_key
```

## Example-specific extraction hints
- Extract `fastedge::proxywasm::secret::get("API_KEY")` pattern — returns `Result<Option<Vec<u8>>, u32>`, chain with `.ok().flatten().and_then(|v| String::from_utf8(v).ok())` for safe conversion
- Show request header extraction: `self.get_http_request_header("X-API-Key")` returning `Option<String>`
- Show validation flow: missing key returns 401 with `WWW-Authenticate: API-Key` header, invalid key returns 403
- Show header stripping: `self.set_http_request_header("X-API-Key", None)` to remove the API key before forwarding to upstream
- Show `self.send_http_response(status, headers, body)` with appropriate status codes and error bodies
- CDN pattern: all validation in `on_http_request_headers`; `Action::Pause` to block, `Action::Continue` to allow
- "When to Use" hint: user wants to validate API keys against a stored secret at the CDN layer — simpler alternative to JWT when token expiry and claims are not needed
