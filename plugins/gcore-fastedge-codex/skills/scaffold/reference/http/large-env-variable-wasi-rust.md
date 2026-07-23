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
capabilities: [large-env-variable, dictionary]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/large_env_variable
---

# Large Environment Variable — WASI HTTP (Rust)

Feature blueprint for reading large environment variables (> 64 KB) using the `fastedge::dictionary` API in a WASI-based HTTP app.

---

## When to Use

Use this blueprint when the app needs to read an environment variable whose value may exceed the **64 KB WASI environment variable size limit** — for example:

- Large JSON configuration blobs
- PEM certificates
- Policy documents

For variables under 64 KB, use `std::env::var("KEY")` instead — it is the standard, idiomatic Rust approach and does not require the `fastedge` crate.

| Method | Use when |
|--------|----------|
| `std::env::var("KEY")` | Variable value is under 64 KB (most cases) |
| `fastedge::dictionary::get("KEY")` | Variable value may exceed the 64 KB WASI env var size limit |

---

## API Reference

### `fastedge::dictionary::get`

```rust
pub fn get(name: &str) -> Option<String>
```

- **Parameter**: `name` — environment variable key name (string slice)
- **Returns**: `Option<String>` — `Some(value)` if the variable exists, `None` if absent
- **Constraint**: Bypasses the 64 KB WASI environment variable size limit
- **Safe fallback**: Use `.unwrap_or_default()` to return an empty `String` when the variable is absent

---

## Required Dependencies

```toml
[dependencies]
wstd = "0.6"
fastedge = "0.4"
anyhow = "1"
```

The `fastedge` crate must be added alongside `wstd`. The `dictionary` module is part of the `fastedge` crate.

---

## Required Configuration

| Environment Variable | Type | Description |
|---|---|---|
| `LARGE_CONFIG` | String (any size) | Large configuration payload (e.g. JSON, PEM certificate) |

---

## Code Pattern

```rust
use fastedge::dictionary;
use wstd::http::body::Body;
use wstd::http::{Request, Response};

#[wstd::http_server]
async fn main(_request: Request<Body>) -> anyhow::Result<Response<Body>> {
    // Use dictionary::get for environment variables that may exceed 64KB.
    // For normal-sized env vars, use std::env::var() instead.
    let config = dictionary::get("LARGE_CONFIG").unwrap_or_default();

    let size = config.len();

    Ok(Response::builder()
        .status(200)
        .body(Body::from(format!(
            "LARGE_CONFIG loaded: {} bytes",
            size
        )))?)
}
```

---

## Crate Structure

```toml
[package]
name = "large_env_variable"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
```

The crate type must be `cdylib` for WASM/WASI compilation.

---

## Key Constraints

- `fastedge::dictionary::get` is only required when the value may exceed 64 KB; using it for small variables is unnecessary overhead.
- `std::env::var()` is the preferred method for all normal-sized environment variables — do not replace it with `dictionary::get` without a specific reason.
- The `dictionary` API does not validate or parse the value — the application is responsible for deserializing the content (e.g. JSON parsing).
- Returns `Option<String>`, not `Result` — missing variables produce `None`, not an error.

---

## See Also

- http-base reference (base skeleton for WASI HTTP apps)
- fastedge-sdk-rust SDK reference (full `fastedge` crate API)
- platform-overview reference (environment variable limits and configuration)
