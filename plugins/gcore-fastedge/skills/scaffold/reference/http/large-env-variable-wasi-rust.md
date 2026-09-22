<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-rust
      ref: main
      commit: 6eedcca9d5c0ddd4ff79ca475965393891da2d75
      updated: 2026-09-22
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

## Source Material

### FILE: examples/http/wasi/large_env_variable/src/lib.rs

```rust
/*
* Copyright 2025 G-Core Innovations SARL
*/
/*
Example WASI-HTTP app demonstrating access to large environment variables.

Uses `fastedge::dictionary` to read environment variables that may exceed
the 64KB WASI environment variable size limit.

For normal-sized environment variables (< 64KB), prefer `std::env::var()`
instead. The dictionary API is only required when your variable value
may be larger than 64KB.

Required configuration:
  - Environment variable: LARGE_CONFIG (a large configuration payload, e.g. JSON)
*/

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


### FILE: examples/http/wasi/large_env_variable/Cargo.toml

```toml
[workspace]

[package]
name = "large_env_variable"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
wstd = "0.6"
fastedge = "0.4"
anyhow = "1"
```


### FILE: examples/http/wasi/large_env_variable/README.md

```
[← Back to examples](../../../README.md)

# Large Environment Variable (WASI)

Demonstrates how to read **large environment variables** (> 64KB) using `fastedge::dictionary`.

## When to use `dictionary` vs `std::env`

| Method | Use when |
|--------|----------|
| `std::env::var("KEY")` | Variable value is under 64KB (most cases) |
| `fastedge::dictionary::get("KEY")` | Variable value may exceed the 64KB WASI env var size limit |

The WASI environment variable interface has a **64KB size limit** per variable. If your app needs to read larger values (e.g. large JSON configs, certificates, policy documents), use the `dictionary` API which bypasses this limit.

For all other environment variable access, prefer `std::env::var()` as it is the standard, idiomatic Rust approach.

## Required configuration

- **Environment variable**: `LARGE_CONFIG` - a large configuration payload (e.g. JSON, PEM certificate)
```
