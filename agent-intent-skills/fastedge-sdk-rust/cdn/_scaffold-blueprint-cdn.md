# CDN Scaffold Blueprint Instructions

> For shared output format, cross-referencing rules, and exclusions see [_scaffold-blueprint-base.md](../_scaffold-blueprint-base.md)

This file adds CDN-specific structure for scaffold blueprint intent skills in the `cdn/` directory.

### Required sections (in this order)

1. **When to Use** — 1-2 sentences describing when this blueprint should be selected. The agent uses this for matching against user intent.
2. **Dependencies to Add** — Cargo.toml dependency entries to merge into the base skeleton's Cargo.toml.
3. **Files to Create** — complete content of any new files this feature adds.
4. **Files to Modify** — for each existing base skeleton file that needs changes:
   - `use` statements to add
   - Code to insert into the handler, with comments indicating placement
   - Which proxy-wasm lifecycle hook(s) the feature code goes into (`on_http_request_headers`, `on_http_request_body`, `on_http_response_headers`, `on_http_response_body`)
5. **Build Notes** — any special build steps, feature flags, or caveats

### CDN host service signatures — authoritative quick-reference

Always document return types as they appear in the function signature, **not** as they appear after chaining (e.g., after `.unwrap_or_default()` or `.ok().flatten()`). Verify against this table:

| Function | Return type |
|----------|-------------|
| `fastedge::proxywasm::secret::get(key)` | `Result<Option<Vec<u8>>, u32>` |
| `fastedge::proxywasm::secret::get_effective_at(key, at)` | `Result<Option<Vec<u8>>, u32>` |
| `fastedge::proxywasm::dictionary::get(key)` | `Option<String>` |
| `fastedge::proxywasm::key_value::Store::new()` | `Result<Self, Error>` |
| `fastedge::proxywasm::key_value::Store::open(name)` | `Result<Self, Error>` |
| `fastedge::proxywasm::key_value::Store::get(key)` | `Result<Option<Vec<u8>>, Error>` |
| `fastedge::proxywasm::key_value::Store::scan(pattern)` | `Result<Vec<String>, Error>` |
| `fastedge::proxywasm::key_value::Store::zrange_by_score(key, min, max)` | `Result<Vec<(Vec<u8>, f64)>, Error>` |
| `fastedge::proxywasm::key_value::Store::zscan(key, pattern)` | `Result<Vec<(Vec<u8>, f64)>, Error>` |
| `fastedge::proxywasm::key_value::Store::bf_exists(key, item)` | `Result<bool, Error>` |

Key differences from the HTTP (Component Model) equivalents:
- **secret**: error type is `u32` (raw host status code), NOT the typed `Error` enum used in HTTP apps
- **dictionary**: returns `Option<String>`, NOT bare `String` — use `.unwrap_or_default()` for fallback
- **key_value**: uses a typed `Error` enum (same pattern as HTTP, but via ProxyWasm FFI)

### `Vec<u8>` decoding — always show safe conversion patterns

Many CDN APIs return `Vec<u8>` or `Option<Vec<u8>>`. Never describe the conversion as just "use `String::from_utf8`" — that returns a `Result` and bare `.unwrap()` panics on invalid UTF-8. Always show the full safe chain:

- **For `Option<Vec<u8>>`** (properties, KV get): `.and_then(|b| String::from_utf8(b).ok()).unwrap_or_default()`
- **For `Result<Option<Vec<u8>>, _>`** (secret get): `.ok().flatten().and_then(|v| String::from_utf8(v).ok())`

These match the patterns in the CDN apps reference (`cdn-apps-rust.md`). Do not abbreviate to just `String::from_utf8` without the `.ok()` error handling.

### Request property encodings — do not invent encodings

All `get_property` request properties are **plain UTF-8 strings** except `response.status` (2-byte big-endian `u16`). There are no "null-delimited", "multi-value", or other special encodings. If a property's encoding is not explicitly documented in the CDN apps reference (`cdn-apps-rust.md`, Request Properties table), treat it as a plain UTF-8 string. Do not infer or fabricate encoding schemes.

### Header removal pitfall — do not attribute to nginx

Passing `None` (Rust) or calling `remove` (AS) to remove a header on the FastEdge CDN platform **sets the header value to an empty string** rather than truly removing it. This is a **FastEdge platform limitation**, not generic nginx or Envoy behavior. Do not attribute it to "nginx" or any underlying infrastructure.

When documenting header removal, always:
1. State the behavior definitively ("sets to empty string"), not with hedging ("may set to empty string")
2. Attribute to "FastEdge CDN platform", not "nginx"
3. Include the recommended workaround: when checking for header absence, test for both a missing value and an empty string
