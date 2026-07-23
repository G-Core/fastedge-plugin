# Synthesis Instructions: host-services-rust.md

> For shared cross-referencing rules, extraction rules, and accuracy constraints see [_docs-pattern-base.md](./_docs-pattern-base.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/host-services-rust.md`

## Audience
AI agents helping developers use FastEdge host services (KV, secrets, dictionary) in Rust WASM apps.

## Output goal
A complete reference for all host-provided service modules. Agents use this to generate correct code that reads KV stores, accesses secrets, and uses configuration — they need exact method signatures and return types.

## Required sections (in this order)

1. **Key-Value Storage** (`fastedge::key_value`) — Complete `Store` API as a table: method | signature | description. Critical accuracy for return types:
   - `new() -> Result<Self, Error>` — open default store
   - `open(name: &str) -> Result<Self, Error>` — open named store
   - `get(&self, key: &str) -> Result<Option<Vec<u8>>, Error>` — returns raw bytes, NOT String
   - `scan(&self, pattern: &str) -> Result<Vec<String>, Error>` — glob-style key scan
   - `zrange_by_score(&self, key: &str, min: f64, max: f64) -> Result<Vec<(Vec<u8>, f64)>, Error>` — sorted set range query
   - `zscan(&self, key: &str, pattern: &str) -> Result<Vec<(Vec<u8>, f64)>, Error>` — sorted set pattern scan
   - `bf_exists(&self, key: &str, item: &str) -> Result<bool, Error>` — bloom filter membership
   - Code example showing open → get → decode pattern

2. **Secret Management** (`fastedge::secret`) — `get(key: &str)` and `get_effective_at(key: &str, at: u32)` with return types. Note that `at` is a Unix timestamp (`u32`). Security note: never log or return secret values.

3. **Dictionary** (`fastedge::dictionary`) — `get(key: &str) -> Option<String>`. One-line comparison: dictionary = read-only config, KV = persistent data, secrets = encrypted credentials.

4. **Utilities** (`fastedge::utils`) — `set_user_diag(value: &str)` for platform log diagnostics.

5. **Feature gating** — All modules require `proxywasm` feature (enabled by default).

## What to exclude
- ProxyWasm FFI internals (`extern "C"` functions)
- Core HTTP handling (covered by the SDK API reference)
- Internal error conversion details
- `proxy_get_property` / `proxy_set_property` raw FFI

## Quality bar
Method signatures must be copied verbatim from source. Return types are the single most important thing to get right — agents generating code with wrong return types produce compilation errors.
