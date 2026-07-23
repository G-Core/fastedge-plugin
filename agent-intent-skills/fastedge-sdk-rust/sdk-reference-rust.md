# Synthesis Instructions: sdk-reference-rust.md

> For shared cross-referencing rules, extraction rules, and accuracy constraints see [_docs-pattern-base.md](./_docs-pattern-base.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/sdk-reference-rust.md`

## Audience
AI agents helping developers build FastEdge WASM applications in Rust.

## Output goal
A concise, decision-dense API reference for the `fastedge` crate. Agents use this to generate correct Rust code — they do not need background explanation of how WASM or component model works.

## Required sections (in this order)

1. **Quick Start** — Cargo.toml setup (crate name + version from source), minimal `#[fastedge::http]` handler, build command (`cargo build --target wasm32-wasip1 --release`)

2. **Handler Macros** — Side-by-side comparison of the two handler patterns:
   - `#[fastedge::http]` — sync, signature `fn(Request<Body>) -> Result<Response<Body>>`, error → HTTP 500
   - `#[wstd::http_server]` — async (recommended for new apps), uses `wstd` crate, built with `cargo component build`
   - Clear recommendation: prefer `#[wstd::http_server]` for new apps

3. **Body Type** — `fastedge::body::Body` constructors and methods as a table. Critical accuracy:
   - `from(String)` / `from(&str)` → content-type `text/plain; charset=utf-8`
   - `from(Vec<u8>)` / `from(&[u8])` → content-type `application/octet-stream`
   - `TryFrom<serde_json::Value>` (requires `json` feature) → `application/json`
   - `empty()` → default body
   - `content_type() -> String`
   - `Deref<Target = Bytes>` for raw byte access

4. **Outbound HTTP** — `fastedge::send_request(req: http::Request<Body>) -> Result<http::Response<Body>, Error>` with request builder pattern example

5. **Error Enum** — All `fastedge::Error` variants as a table: variant name | description | when it occurs

6. **Feature Flags** — `proxywasm` (default), `json` (serde_json support)

7. **Re-exports** — `fastedge::http` re-exports the `http` crate; supported methods: GET, POST, PUT, DELETE, HEAD, PATCH, OPTIONS

## What to exclude
- Host services (key-value, secret, dictionary) — covered by the host services reference
- WIT binding internals, `wit_bindgen::generate!`
- `#[doc(hidden)]` items
- Type conversion implementation details
- Build system or CI details
- Example catalog

## Quality bar
All type signatures must match the source code exactly. When the source uses `::http::Request<body::Body>`, write `http::Request<Body>` (the user-facing import path, not the internal path).
