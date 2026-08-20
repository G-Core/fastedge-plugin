<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-rust
      ref: main
      commit: 6347a7c2fda0d03e66f1214db5eec041c16801b7
      updated: 2026-08-20
-->

---
type: feature
app_type: http
languages: [rust]
capabilities: [outbound-fetch]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/outbound_fetch
---

# Outbound Fetch (WASI, Rust)

Proxy an upstream HTTP request and return the response verbatim — status, headers, and body pass through unchanged without buffering.

## When to Use

Use this pattern when:
- The handler must forward an inbound request to an upstream HTTP origin and return the upstream response without modification.
- The upstream body must not be buffered — chunks should stream to the client as upstream produces them.
- No transformation of status, headers, or body is required.

For reading and reshaping the upstream body, see the `outbound-modify-response` example. For generating a streaming response body from within the handler, see the `streaming` example.

## Dependencies

```toml
[dependencies]
wstd = "0.6"
anyhow = "1"
```

Crate type must be `cdylib`:

```toml
[lib]
crate-type = ["cdylib"]
```

## Core API

### `wstd::http::Client`

| Item | Signature | Notes |
|---|---|---|
| Constructor | `Client::new() -> Client` | Creates a new outbound HTTP client. No configuration required for basic use. |
| Send request | `Client::send(req: Request<Body>) -> impl Future<Output = Result<Response<Body>>>` | Async. Returns the upstream `Response<Body>` or an error. Must be `.await`ed. |

### `wstd::http::Request`

| Item | Signature | Notes |
|---|---|---|
| GET builder | `Request::get(uri: impl AsRef<str>) -> Builder` | Starts a request builder for a GET method. |
| Set body | `Builder::body(body: Body) -> Result<Request<Body>>` | Finalizes the request. Returns `Err` if URI or headers are malformed. |
| Empty body | `Body::empty() -> Body` | Produces an empty body suitable for GET requests. |

### `wstd::http::Response`

| Item | Signature | Notes |
|---|---|---|
| Split parts | `Response::into_parts() -> (Parts, Body)` | Destructures response into `Parts` (status, headers, extensions) and `Body`. |
| Reconstruct | `Response::new(body: Body) -> Response<Body>` | Creates a new response with the given body; status and headers are defaults until mutated. |
| Set status | `*response.status_mut() = parts.status` | Mutates status in place from the upstream `Parts`. |
| Set headers | `*response.headers_mut() = parts.headers` | Mutates headers in place from the upstream `Parts`. |

## Complete Example

```rust
use anyhow::anyhow;
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

    // Pass through without calling .contents() — body streams to client as upstream produces it.
    let (parts, body) = upstream_resp.into_parts();
    let mut response = Response::new(body);
    *response.status_mut() = parts.status;
    *response.headers_mut() = parts.headers;
    Ok(response)
}
```

## Pass-Through Pattern

The key to transparent proxying is splitting the upstream response with `into_parts()` and reconstructing a new `Response` from those parts:

1. `upstream_resp.into_parts()` — separates `Parts` (status, headers) from `Body`.
2. `Response::new(body)` — creates a fresh response carrying the upstream body handle.
3. `status_mut()` / `headers_mut()` — copies upstream status and headers onto the new response.

**Streaming guarantee**: `.contents()` is never called. The body handle is passed directly to the runtime, so upstream data chunks flow to the client without being fully buffered in the handler.

## Error Conditions

| Error site | Condition | Handling |
|---|---|---|
| `Request::get(...).body(...)` | Malformed URI or header values | Returns `Err`; mapped with `anyhow!("failed to build request: {e}")` |
| `Client::send(...).await` | Network failure, DNS resolution failure, upstream unreachable | Returns `Err`; mapped with `anyhow!("outbound request failed: {e}")` |

Both errors propagate via `?` and result in a 500-class response from the FastEdge runtime.

## Constraints

- The inbound request (`_request`) is ignored in this example; the upstream URL is hardcoded. In production usage the URL would typically be derived from the inbound request or handler configuration.
- Only GET with an empty body is shown. `Client::send` accepts any `Request<Body>` — other methods and bodies follow the same pattern.
- No response body transformation is possible without calling `.contents().await`, which would buffer the full body and break streaming.

## See Also

- `outbound-modify-response` (WASI, Rust) — fetches upstream and reshapes the body into a new JSON response
- `streaming` (WASI, Rust) — handler that generates its own streaming response without an upstream fetch
- `outbound-fetch` (JavaScript) — mirror of this example in the FastEdge SDK JS

## Source Material

### FILE: examples/http/wasi/outbound_fetch/src/lib.rs

```rust
/*
 * Copyright 2025 G-Core Innovations SARL
 */
/*
Minimal outbound fetch example.

Makes a GET request to an upstream HTTP origin and returns the upstream
response verbatim — status, headers, and body pass through unchanged.

For a variant that reads and transforms the upstream body, see
`outbound_modify_response/`. For a streaming-response demo, see `streaming/`.

Mirror of the FastEdge-sdk-js `outbound-fetch` example.
*/

use anyhow::anyhow;
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

    // Return the upstream response verbatim. The body is passed through
    // without calling `.contents()`, so it streams to the client as upstream
    // produces it.
    let (parts, body) = upstream_resp.into_parts();
    let mut response = Response::new(body);
    *response.status_mut() = parts.status;
    *response.headers_mut() = parts.headers;
    Ok(response)
}
```


### FILE: examples/http/wasi/outbound_fetch/Cargo.toml

```toml
[workspace]

[package]
name = "outbound_fetch"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
wstd = "0.6"
anyhow = "1"
```


### FILE: examples/http/wasi/outbound_fetch/README.md

```
[← Back to examples](../../../README.md)

# Outbound Fetch (WASI)

Fetch data from an outbound HTTP origin and return the response directly — status, headers,
and body pass through unchanged.

The body is never buffered (no `.contents().await`), so upstream chunks stream to the client
as they arrive.

## Related

- [outbound_modify_response](../outbound_modify_response/) — same fetch, but reads the body
  and reshapes it into a new JSON response.
- [streaming](../streaming/) — a handler that generates its own streaming response body.
- Mirror of `FastEdge-sdk-js/examples/outbound-fetch/`.
```
