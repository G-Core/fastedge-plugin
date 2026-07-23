# Synthesis Instructions: examples-ab-testing-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-ab-testing-rust.md`

## Example-specific extraction hints
- API focus: `self.get_http_request_header("Cookie")` for cookie parsing, `self.get_current_time()` for variant randomization, `self.set_property(vec!["request.path"], Some(bytes))` for path rewriting, `self.add_http_response_header("Set-Cookie", &cookie)` for variant persistence
- Show cookie parsing: split on `;`, match `name=value` pattern, helper function `get_cookie_value()`
- Show variant assignment: `get_current_time().duration_since(UNIX_EPOCH).as_millis() % 2` for 50/50 split
- Show cross-hook state: struct fields (`variant`, `experiment_name`) set in request hook, read in response hook for Set-Cookie
- Common patterns: check for existing cookie → assign if new → rewrite path → add experiment headers to request → set cookie in response
- Show env var configuration: `EXPERIMENT_NAME`, `VARIANT_A_PATH`, `VARIANT_B_PATH`
- Gotchas: cookie name convention `fe_exp_<name>`, `SameSite=Lax` for cookie security, cross-hook state via struct fields (not `set_property` here), `get_current_time()` returns `SystemTime` requiring `duration_since(UNIX_EPOCH)`
