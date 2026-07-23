# Synthesis Instructions: examples-custom-rust.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-custom-rust.md`

## Example-specific extraction hints
- API focus: `self.get_property(vec!["request.path"])` for path extraction; `self.send_http_response(code, vec![], body)` for synthetic short-circuit responses; `Action::Pause` to stop the filter chain after sending a response; `Action::Continue` to pass through to origin
- Show path parsing pattern: decode `request.path` from `Vec<u8>`, trim leading `/`, split on `/`, extract ordered segments as status code (first) and optional delay milliseconds (second)
- Show `send_http_response` branching: valid 1–599 code sends that status; 0 or 200 falls through with `Action::Continue`; invalid code or parse error returns 400 Bad Request
- Common patterns: early return with `Action::Pause` after `send_http_response`; `std::str::from_utf8` for inline property decoding; iterator `next()` for positional segment extraction without indexing
- Gotchas: `send_http_response` must be followed by `Action::Pause` — returning `Action::Continue` after a synthetic response leads to undefined behavior; `get_property(vec!["request.path"])` always includes the leading `/` — trim it before splitting; status code 0 is treated as pass-through (same as 200) in this example
