# Synthesis Instructions: ab-testing-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/ab-testing-rust.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [rust]
capabilities: [ab-testing, cookies, traffic-splitting]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/ab_testing
```

## Example-specific extraction hints
- Extract cookie-based variant assignment: parse `Cookie` header to find existing experiment cookie, assign new variant using `self.get_current_time()` for randomization
- Show cookie parsing helper: `get_cookie_value(cookie_header, name)` function that splits on `;` and matches `name=value`
- Show path rewriting: read `request.path` property, prepend variant-specific path prefix, write back with `self.set_property(vec!["request.path"], Some(bytes))`
- Show Set-Cookie in response: `on_http_response_headers` adds `Set-Cookie` header with `fe_exp_<name>=<variant>; Path=/; Max-Age=86400; SameSite=Lax`
- Show cross-hook state via struct fields (`variant: String`, `experiment_name: String`) — request hook assigns, response hook reads
- Show env var configuration: `EXPERIMENT_NAME`, `VARIANT_A_PATH`, `VARIANT_B_PATH`
- Show upstream visibility headers: `X-Experiment` and `X-Variant` added to request
- CDN pattern: uses both `on_http_request_headers` (variant assignment + path rewrite) and `on_http_response_headers` (Set-Cookie)
- "When to Use" hint: user wants to split traffic between A/B variants using cookies and path rewriting at the CDN layer
