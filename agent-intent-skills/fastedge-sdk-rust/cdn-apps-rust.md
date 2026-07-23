# Synthesis Instructions: cdn-apps-rust.md

> For shared cross-referencing rules, extraction rules, and accuracy constraints see [_docs-pattern-base.md](./_docs-pattern-base.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn-apps-rust.md`

## Audience
AI agents helping developers build CDN apps (proxy-wasm filters) with the FastEdge Rust SDK.

## Output goal
A complete, decision-dense reference for building CDN apps that run as proxy-wasm filters inside Gcore's CDN proxy layer. Agents use this to generate correct proxy-wasm Rust code — they do not need background explanation of how CDN infrastructure works.

## Required sections (in this order)

1. **CDN Apps vs HTTP Apps** — Comparison table covering: build target, entry point, request/response model, host services feature flag, crate framework. Make it immediately clear when to use CDN apps vs HTTP apps.

2. **Cargo.toml** — Two tiers:
   - Tier 1: Basic CDN app (proxy-wasm only, no FastEdge host services)
   - Tier 2: CDN app with FastEdge host services (requires `fastedge` with `features = ["proxywasm"]`)
   - Explain that the `proxywasm` feature flag is required to access `fastedge::proxywasm::*`

3. **Build** — Build command (`cargo build --target wasm32-wasip1 --release`). Note that CDN apps share the `wasm32-wasip1` target with basic HTTP apps; only async WASI HTTP apps use `wasm32-wasip2`.

4. **Proxy-Wasm Lifecycle** — The three-layer structure:
   - Entry point: `proxy_wasm::main!` macro, `set_log_level`, `set_root_context`
   - Root context: singleton, implements `RootContext` + `Context`, creates HTTP contexts via `create_http_context`
   - HTTP context: per-request, implements `HttpContext` + `Context`
   - Include code examples for each layer

5. **Lifecycle Callbacks** — Table of `HttpContext` callbacks:
   - `on_http_request_headers`, `on_http_request_body`, `on_http_response_headers`, `on_http_response_body`
   - Phase, signature, description for each
   - Note that all have default no-op implementations

6. **Action Return Values** — Table: `Action::Continue`, `Action::Pause`, `Action::StopIterationAndBuffer` with meaning and when to use each. Include body buffering pattern example.

7. **Request and Response Manipulation** — Sub-sections:
   - Reading headers: `get_http_request_header`, `get_http_response_header`
   - Reading properties: `get_property` with `Option<Vec<u8>>` return type
   - Modifying headers: `add_http_request_header`, `set_http_request_header`, `add_http_response_header`, `set_http_response_header`
   - Generating responses: `send_http_response` signature and usage with `Action::Pause`

8. **Request Properties** — Table of available properties:
   - `request.path`, `request.query`, `request.country` (UTF-8 strings)
   - `response.status` (2-byte big-endian u16 — must NOT use `String::from_utf8`)
   - Include decoding examples for both string and binary properties

9. **Host Services for CDN Apps** — Sub-sections for each `fastedge::proxywasm::*` module:
   - Key-Value (`fastedge::proxywasm::key_value::Store`) — all methods as a table, `Error` enum, example
   - Secrets (`fastedge::proxywasm::secret`) — `get` and `get_effective_at`, note `u32` error type difference from Component Model
   - Dictionary (`fastedge::proxywasm::dictionary`) — `get` returns `Option<String>`, example
   - Diagnostics (`fastedge::proxywasm::utils`) — `set_user_diag`, panics on non-zero status
   - Environment variables — `std::env::var()`, no proxy-wasm-specific API needed
   - Logging — `println!`, `proxy_wasm::hostcalls::log`, `log` crate macros. Note: only stdout is captured; stderr is silently discarded.

10. **API Comparison: HTTP vs CDN** — Side-by-side table of equivalent APIs across Component Model (HTTP apps) and ProxyWasm (CDN apps): key-value, secrets, dictionary, diagnostics, error types, cargo feature, build target, handler.

11. **See Also** — Plain-text topic references (not file links):
    - SDK API reference — HTTP app handler macro, `Body` type, outbound HTTP
    - Host services reference — Component Model host services for HTTP apps

## What to exclude
- HTTP app handler patterns (`#[fastedge::http]`, `#[wstd::http_server]`) — covered by the SDK API reference
- Component Model host service APIs (non-proxywasm) — covered by the host services reference
- WIT binding internals
- Build system or CI details
- Example catalog or project scaffolding

## Quality bar
- All type signatures must match the source code exactly
- The `proxywasm` feature flag requirement must be prominently documented
- The `response.status` binary encoding must include the correct decoding pattern (big-endian u16) with an explicit warning against `String::from_utf8`
- Host service API differences between Component Model and ProxyWasm must be clearly called out (especially the `u32` error type for secrets)
- Every code example must show the full proxy-wasm boilerplate (entry point, root context, HTTP context) so agents can produce runnable code
