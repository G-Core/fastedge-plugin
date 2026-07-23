<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-rust
      ref: main
      commit: 6347a7c2fda0d03e66f1214db5eec041c16801b7
      updated: 2026-06-16
-->

---
type: feature
app_type: http
languages: [rust]
capabilities: [headers, env-vars]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/headers
---

# headers-wasi-rust — HTTP Headers Feature (Rust / WASI)

## Purpose

Echoes all incoming request headers back in the response and appends a custom `x-my-custom-header` whose value is sourced from an environment variable.

Use this pattern when the app needs to inspect, copy, or inject HTTP headers — for example: echoing request headers for debugging, forwarding headers downstream, or injecting environment-variable values into response headers.

## When to Use

- User wants to read and reflect request headers in the response
- User wants to add custom response headers from environment variables
- User needs a mutable builder pattern for conditionally assembling response headers

## Dependencies

No extra dependencies beyond the base skeleton.

```toml
[dependencies]
wstd = "0.6"
anyhow = "1"
```

## Environment Variables

| Variable | Required | Type | Description |
|---|---|---|---|
| `MY_CUSTOM_ENV_VAR` | No | String | Value placed in the `x-my-custom-header` response header. Defaults to empty string if unset. |

## Core Pattern

```rust
use std::env;
use wstd::http::body::Body;
use wstd::http::{Request, Response};

#[wstd::http_server]
async fn main(request: Request<Body>) -> anyhow::Result<Response<Body>> {
    let custom_env_var = env::var("MY_CUSTOM_ENV_VAR").unwrap_or_default();

    let mut builder = Response::builder().status(200);

    // Copy request headers to response
    for (name, value) in request.headers() {
        builder = builder.header(name.as_str(), value);
    }

    // Add custom header from env var
    builder = builder.header("x-my-custom-header", &custom_env_var);

    Ok(builder.body(Body::from(
        "Returned all headers with a custom header added",
    ))?)
}
```

## Key APIs

### `request.headers()`
- Returns an iterator over all incoming request headers as `(HeaderName, HeaderValue)` pairs.
- Used to copy request headers onto the response builder.

### `Response::builder().status(u16)`
- Creates a mutable `ResponseBuilder` initialized with the given HTTP status code.
- Must be `let mut` to allow chained `.header()` calls inside a loop.

### `builder.header(name, value)`
- Signature: `.header(name: impl AsRef<str>, value: impl AsRef<[u8]>)`
- Appends a single header to the builder. Call repeatedly in a loop to copy multiple headers.
- `name.as_str()` converts `HeaderName` to `&str` for compatibility.

### `std::env::var("KEY").unwrap_or_default()`
- Reads an optional environment variable. Returns an empty `String` if the variable is unset or invalid UTF-8.

## Mutable Builder Pattern

Initialize the builder once, then reassign inside a loop:

```rust
let mut builder = Response::builder().status(200);
for (name, value) in request.headers() {
    builder = builder.header(name.as_str(), value);
}
builder = builder.header("x-my-custom-header", &custom_env_var);
```

This pattern is required when the number of headers is not known at compile time.

## Response Shape

```
HTTP/1.1 200 OK
x-my-custom-header: <MY_CUSTOM_ENV_VAR value>
<...all other request headers echoed back...>

Returned all headers with a custom header added
```

## Build

```sh
cargo build --release
# Output: target/wasm32-wasip2/release/headers.wasm
```

Crate type must be `cdylib`:

```toml
[lib]
crate-type = ["cdylib"]
```

## See Also

- http-base skeleton (base_skeleton for this feature)
- deploy skill reference (uploading the compiled .wasm binary)
- FastEdge-sdk-rust platform overview (environment variable injection at runtime)
