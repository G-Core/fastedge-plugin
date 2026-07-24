<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-rust
      ref: main
      commit: 6347a7c2fda0d03e66f1214db5eec041c16801b7
      updated: 2026-07-23
-->

---
type: feature
app_type: http
languages: [rust]
capabilities: [outbound-fetch, json-transform]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/outbound_modify_response
---

# Feature: Outbound Fetch with Response Transformation (WASI, Rust)

## When to Use

Use this blueprint when the handler must fetch JSON from an upstream service, reshape or filter the response data, and return a new JSON response with a custom structure. This goes beyond a simple proxy — the upstream body is fully consumed, parsed, and re-serialized before being returned to the client.

## Dependencies

Add to `Cargo.toml` in addition to the base skeleton dependencies:

```toml
serde_json = "1"
```

Full `[dependencies]` block:

```toml
[dependencies]
wstd = "0.6"
anyhow = "1"
serde_json = "1"
```

`[lib]` must declare `crate-type = ["cdylib"]`.

## Key Imports

```rust
use anyhow::anyhow;
use serde_json::{Value, json};
use wstd::http::body::Body;
use wstd::http::{Client, Request, Response};
```

## Transform Pipeline

### 1. Build and send the outbound request

```rust
let upstream_req = Request::get("http://jsonplaceholder.typicode.com/users")
    .body(Body::empty())
    .map_err(|e| anyhow!("failed to build request: {e}"))?;

let upstream_resp = Client::new()
    .send(upstream_req)
    .await
    .map_err(|e| anyhow!("outbound request failed: {e}"))?;
```

- `Request::get(url)` — constructs a GET request builder.
- `.body(Body::empty())` — attaches an empty body; returns `Result<Request<Body>, _>`.
- `Client::new().send(req).await` — sends the request asynchronously; returns `Result<Response<Body>, _>`.

### 2. Consume the upstream body

```rust
let (_, mut body) = upstream_resp.into_parts();
let body_bytes = body.contents().await?;
```

- `into_parts()` — splits `Response<Body>` into `(Parts, Body)`. The parts (status, headers) are discarded here.
- `body.contents().await?` — materializes the full body as `&[u8]`. This is async and must be awaited. `body` must be `mut`.

### 3. Parse and reshape JSON

```rust
let users: Value = serde_json::from_slice(body_bytes)?;

let sliced_users = match users.as_array() {
    Some(arr) => Value::Array(arr.iter().take(5).cloned().collect()),
    None => Value::Array(vec![]),
};

let result = json!({
    "users": sliced_users,
    "total": 5,
    "skip": 0,
    "limit": 30,
});
```

- `serde_json::from_slice(&[u8])` — deserializes bytes into `serde_json::Value`; returns `Result<Value, serde_json::Error>`.
- `Value::as_array()` — returns `Option<&Vec<Value>>`.
- `json!({...})` macro — constructs a `serde_json::Value` from a JSON literal; fields can embed computed `Value` variables.

### 4. Return a new response with JSON content type

```rust
Ok(Response::builder()
    .status(200)
    .header("content-type", "application/json")
    .body(Body::from(result.to_string()))?)
```

- `result.to_string()` — serializes the `Value` to a JSON string.
- `Body::from(String)` — wraps the string as a response body.
- `header("content-type", "application/json")` — must be set explicitly; the upstream `content-type` is not forwarded.

## Complete Handler

```rust
#[wstd::http_server]
async fn main(_request: Request<Body>) -> anyhow::Result<Response<Body>> {
    let upstream_req = Request::get("http://jsonplaceholder.typicode.com/users")
        .body(Body::empty())
        .map_err(|e| anyhow!("failed to build request: {e}"))?;

    let upstream_resp = Client::new()
        .send(upstream_req)
        .await
        .map_err(|e| anyhow!("outbound request failed: {e}"))?;

    let (_, mut body) = upstream_resp.into_parts();
    let body_bytes = body.contents().await?;
    let users: Value = serde_json::from_slice(body_bytes)?;

    let sliced_users = match users.as_array() {
        Some(arr) => Value::Array(arr.iter().take(5).cloned().collect()),
        None => Value::Array(vec![]),
    };

    let result = json!({
        "users": sliced_users,
        "total": 5,
        "skip": 0,
        "limit": 30,
    });

    Ok(Response::builder()
        .status(200)
        .header("content-type", "application/json")
        .body(Body::from(result.to_string()))?)
}
```

## API Reference

### `body.contents().await?`

- **Signature**: `async fn contents(&mut self) -> Result<&[u8], _>`
- **Receiver**: `&mut Body`
- **Returns**: Borrowed byte slice of the full body content.
- **Constraints**: Must be awaited. Materializes the complete body in memory — unsuitable for streaming or very large bodies.

### `serde_json::from_slice`

- **Signature**: `fn from_slice<T: DeserializeOwned>(v: &[u8]) -> Result<T, serde_json::Error>`
- **Used as**: `serde_json::from_slice(body_bytes)` → `Result<Value, _>`
- **Error**: Returns `Err` if input is not valid JSON.

### `serde_json::json!` macro

- **Usage**: `json!({ "key": expr, ... })` → `serde_json::Value`
- **Accepts**: JSON literal syntax with embedded Rust expressions.

### `Response::builder()`

- **Signature**: `fn builder() -> http::response::Builder`
- **Methods**: `.status(u16)`, `.header(key, value)`, `.body(Body)` → `Result<Response<Body>, _>`

### `Client::new().send(req).await`

- **Signature**: `async fn send(&self, req: Request<Body>) -> Result<Response<Body>, _>`
- **Returns**: `Result<Response<Body>, _>`
- **Errors**: Network failure, DNS error, upstream unreachable.

### `Request::get(url)`

- **Signature**: `fn get(uri: impl TryInto<Uri>) -> http::request::Builder`
- **Returns**: A request builder initialized with the GET method and the given URI.

### `into_parts()`

- **Signature**: `fn into_parts(self) -> (Parts, Body)` (on `Response<Body>`)
- **Returns**: Tuple of response metadata (`Parts`: status, headers, extensions) and the body.
- **Note**: Discards `Parts` when only the body is needed. Inspect `Parts.status` if upstream error handling is required.

## Error Conditions

| Site | Error type | Cause |
|---|---|---|
| `Request::get(...).body(...)` | `anyhow!` wrapped | Invalid request construction |
| `Client::new().send(...).await` | `anyhow!` wrapped | Network failure, DNS error, upstream unreachable |
| `body.contents().await?` | propagated via `?` | Body read failure |
| `serde_json::from_slice(...)` | propagated via `?` | Upstream response is not valid JSON |
| `Response::builder()...body(...)` | propagated via `?` | Response construction failure |

## Constraints and Notes

- The incoming `_request` is ignored; this handler always fetches from a hardcoded upstream URL.
- The upstream body is fully buffered in memory via `body.contents().await?`. Do not use this pattern for large or streaming upstream responses.
- `into_parts()` discards all upstream response metadata (status code, headers). If upstream errors must be handled, inspect `Parts.status` before proceeding.
- `serde_json` is not part of the base skeleton — it must be added explicitly to `Cargo.toml`.
- Response `content-type` must be set manually; it is not inherited from the upstream response.

## See Also

- outbound-fetch-wasi-rust (simpler variant — passes upstream response through unchanged)
- http-base skeleton (base handler structure, `#[wstd::http_server]`, `Body`, `Request`, `Response`)
- sdk-reference-rust (full `wstd` API surface)

## Source Material

### FILE: examples/http/wasi/outbound_modify_response/src/lib.rs

```rust
/*
 * Copyright 2025 G-Core Innovations SARL
 */
/*
Outbound fetch with response transformation.

Fetches JSON from an upstream origin, reads and parses the body, reshapes it
into a new JSON object (first 5 users with pagination metadata), and returns
it with a fresh `content-type: application/json` header.

This is the stepping-stone beyond `outbound_fetch/` which just passes the
upstream response through unchanged.

Mirror of the FastEdge-sdk-js `outbound-modify-response` example.
*/

use anyhow::anyhow;
use serde_json::{Value, json};
use wstd::http::body::Body;
use wstd::http::{Client, Request, Response};

#[wstd::http_server]
async fn main(_request: Request<Body>) -> anyhow::Result<Response<Body>> {
    let upstream_req = Request::get("http://jsonplaceholder.typicode.com/users")
        .body(Body::empty())
        .map_err(|e| anyhow!("failed to build request: {e}"))?;

    let upstream_resp = Client::new()
        .send(upstream_req)
        .await
        .map_err(|e| anyhow!("outbound request failed: {e}"))?;

    let (_, mut body) = upstream_resp.into_parts();
    let body_bytes = body.contents().await?;
    let users: Value = serde_json::from_slice(body_bytes)?;

    let sliced_users = match users.as_array() {
        Some(arr) => Value::Array(arr.iter().take(5).cloned().collect()),
        None => Value::Array(vec![]),
    };

    let result = json!({
        "users": sliced_users,
        "total": 5,
        "skip": 0,
        "limit": 30,
    });

    Ok(Response::builder()
        .status(200)
        .header("content-type", "application/json")
        .body(Body::from(result.to_string()))?)
}
```

### FILE: examples/http/wasi/outbound_modify_response/Cargo.toml

```toml
[workspace]

[package]
name = "outbound_modify_response_wasi"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
wstd = "0.6"
anyhow = "1"
serde_json = "1"
```
