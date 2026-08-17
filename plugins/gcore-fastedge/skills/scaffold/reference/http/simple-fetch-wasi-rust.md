<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-rust
      ref: main
      commit: 6347a7c2fda0d03e66f1214db5eec041c16801b7
      updated: 2026-08-17
-->

---
type: feature
app_type: http
languages: [rust]
capabilities: [outbound-fetch, header-driven-routing]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/simple_fetch
---

# Simple Fetch (WASI HTTP, Rust)

Outbound HTTP request to a caller-supplied URL, returning the upstream response directly. Uses the WASI-HTTP interface via the `wstd` crate with an async handler.

## When to Use

Use this pattern when the app must make an outbound HTTP request to a URL specified by the incoming request (via the `x-fetch-url` header) and return the upstream response directly to the caller without decomposing it.

## Crate Dependencies

```toml
[dependencies]
wstd = "0.6"
anyhow = "1"

[lib]
crate-type = ["cdylib"]

[package.metadata.component]
package = "component:simple_fetch"
```

Build target: `wasm32-wasip2` (WASI component model, required for `wstd`).

## Handler Signature

```rust
#[wstd::http_server]
async fn main(request: Request<Body>) -> anyhow::Result<Response<Body>>
```

- Macro: `#[wstd::http_server]`
- Handler is `async`
- Parameter: `Request<wstd::http::body::Body>`
- Return: `anyhow::Result<Response<Body>>`

## Key API Patterns

### Extract Header from Incoming Request

```rust
let target_url = request
    .headers()
    .get("x-fetch-url")
    .and_then(|v| v.to_str().ok())
    .unwrap_or("https://httpbin.org/get")
    .to_string();
```

- `request.headers().get(name)` — returns `Option<&HeaderValue>`
- `.and_then(|v| v.to_str().ok())` — converts to `Option<&str>`, discarding invalid UTF-8
- `.unwrap_or(default)` — fallback value when header is absent or invalid

### Build Outbound Request

```rust
let upstream_req = Request::get(&target_url)
    .header("accept", "application/json")
    .body(Body::empty())
    .map_err(|e| anyhow!("failed to build request: {e}"))?;
```

- `Request::get(url)` — initiates a GET request builder
- `.header(key, value)` — appends a request header
- `.body(Body::empty())` — finalizes with an empty body; returns `Result`
- `.map_err(...)` — converts builder error into `anyhow::Error`

### Send Request and Return Response

```rust
let client = Client::new();
let response = client
    .send(upstream_req)
    .await
    .map_err(|e| anyhow!("request failed: {e}"))?;

Ok(response)
```

- `Client::new()` — constructs a new HTTP client (no configuration)
- `client.send(req).await` — async outbound send; returns `Result<Response<Body>>`
- The `Response<Body>` is returned directly — no decomposition needed

## Request Headers

| Header | Required | Default | Description |
|--------|----------|---------|-------------|
| `x-fetch-url` | No | `https://httpbin.org/get` | URL to fetch outbound |

## Imports

```rust
use anyhow::anyhow;
use wstd::http::body::Body;
use wstd::http::{Client, Request, Response};
```

## Comparison: WASI HTTP vs Basic HTTP

| Aspect | Basic HTTP (`fastedge` crate) | WASI HTTP (`wstd` crate) |
|--------|-------------------------------|--------------------------|
| Handler style | `fn main(req)` — sync | `async fn main(req)` — async |
| Macro | `#[fastedge::http]` | `#[wstd::http_server]` |
| Outbound HTTP | `fastedge::send_request(req)` | `Client::new().send(req).await` |
| Build target | `wasm32-wasip1` | `wasm32-wasip2` |

## Error Conditions

| Condition | Handling |
|-----------|----------|
| Request builder failure | `map_err` converts to `anyhow::Error`; propagated via `?` |
| Outbound send failure | `map_err` converts to `anyhow::Error`; propagated via `?` |
| Missing `x-fetch-url` header | Falls back to `https://httpbin.org/get` |
| Non-UTF-8 header value | `to_str().ok()` returns `None`; fallback default applied |

## Source Material

### FILE: examples/http/wasi/simple_fetch/src/lib.rs

```rust
/*
* Copyright 2025 G-Core Innovations SARL
*/
/*
Example app demonstrating the WASI-HTTP interface via the wstd crate.

The app receives an incoming HTTP request and makes an outbound HTTP request
to the URL specified in the `x-fetch-url` header (defaults to https://httpbin.org/get).

Build with cargo-component:
  cargo component build --release
*/

use anyhow::anyhow;
use wstd::http::body::Body;
use wstd::http::{Client, Request, Response};

#[wstd::http_server]
async fn main(request: Request<Body>) -> anyhow::Result<Response<Body>> {
    let target_url = request
        .headers()
        .get("x-fetch-url")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("https://httpbin.org/get")
        .to_string();

    println!("Fetching: {target_url}");

    let upstream_req = Request::get(&target_url)
        .header("accept", "application/json")
        .body(Body::empty())
        .map_err(|e| anyhow!("failed to build request: {e}"))?;

    let client = Client::new();
    let response = client
        .send(upstream_req)
        .await
        .map_err(|e| anyhow!("request failed: {e}"))?;

    println!("Response status: {}", response.status());

    Ok(response)
}
```

### FILE: examples/http/wasi/simple_fetch/Cargo.toml

```toml
[workspace]

[package]
name = "simple_fetch"
version = "0.1.0"
edition = "2021"
publish = false

[lib]
crate-type = ["cdylib"]

[dependencies]
wstd = "0.6"
anyhow = "1"

[package.metadata.component]
package = "component:simple_fetch"
```

### FILE: examples/http/wasi/simple_fetch/README.md

```
[← Back to examples](../../../README.md)

# Simple Fetch

A minimal example demonstrating outbound HTTP requests using the [WASI-HTTP](https://github.com/WebAssembly/wasi-http) interface via the [`wstd`](https://crates.io/crates/wstd) crate.

Uses the WASI component model with an **async** handler and a proper HTTP client (`wstd::http::Client`). The same async pattern is used by all examples in `examples/http/wasi/`.

## How it works

The app receives an incoming request, reads the target URL from the `x-fetch-url` header, makes an outbound GET request to that URL, and streams the response back to the caller.

If the `x-fetch-url` header is absent, it defaults to `https://httpbin.org/get`.

## Request headers

| Header | Required | Description |
|--------|----------|-------------|
| `x-fetch-url` | No | URL to fetch. Defaults to `https://httpbin.org/get` |

## Example

```bash
curl -H "x-fetch-url: https://httpbin.org/uuid" https://<your-app-domain>/
```

## Build

```bash
cargo build --release
# Output: target/wasm32-wasip2/release/simple_fetch.wasm
```

## Key differences from basic HTTP examples

| | Basic HTTP (`fastedge` crate) | WASI HTTP (`wstd` crate) |
|---|---|---|
| Handler | `fn main(req)` — sync | `async fn main(req)` — async |
| Macro | `#[fastedge::http]` | `#[wstd::http_server]` |
| Outbound HTTP | `fastedge::send_request(req)` | `Client::new().send(req).await` |
| Build target | `wasm32-wasip1` | `wasm32-wasip2` |
```

## See Also

- http-base skeleton (base_skeleton for this feature)
- outbound-fetch capability reference
- wstd crate (crates.io/crates/wstd)
- WASI-HTTP interface specification (WebAssembly/wasi-http)
- FastEdge-sdk-rust examples/http/wasi/ for other WASI async patterns
