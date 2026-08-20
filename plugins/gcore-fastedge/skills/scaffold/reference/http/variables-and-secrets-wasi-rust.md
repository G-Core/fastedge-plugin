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
capabilities: [env-variables, secrets]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/variables_and_secrets
---

# Variables and Secrets (WASI, Rust)

Feature blueprint for reading plain environment variables and encrypted secrets in a FastEdge HTTP app.

## When to Use

Use this blueprint when the app needs to read both plain environment variables and encrypted secrets at runtime — for example, to inject credentials, configuration values, or tokens into request handling or response output without hardcoding them.

## API Reference

### Environment Variables

```rust
std::env::var("NAME") -> Result<String, std::env::VarError>
```

- Reads a plain environment variable by name.
- Returns `Ok(String)` if set, `Err(VarError::NotPresent)` if unset.
- Common pattern: `.unwrap_or_default()` to fall back to an empty string.

### Secrets

```rust
fastedge::secret::get("NAME") -> Result<Option<String>, ...>
```

- Reads an encrypted secret by name.
- Returns `Ok(Some(String))` on success.
- Returns `Ok(None)` if the secret is not set.
- Returns `Err(...)` on access failure.
- Secrets are never exposed in platform logs or configuration UIs.
- Match pattern: `Ok(Some(value)) => value, _ => String::new()` to handle all non-success cases with a fallback.

## Two-Step Read Pattern

```rust
use fastedge::secret;
use std::env;

// Plain environment variable
let username = env::var("USERNAME").unwrap_or_default();

// Encrypted secret
let password = match secret::get("PASSWORD") {
    Ok(Some(value)) => value,
    _ => String::new(),
};
```

## Full Example

```rust
use fastedge::secret;
use std::env;
use wstd::http::body::Body;
use wstd::http::{Request, Response};

#[wstd::http_server]
async fn main(_request: Request<Body>) -> anyhow::Result<Response<Body>> {
    let username = env::var("USERNAME").unwrap_or_default();
    let password = match secret::get("PASSWORD") {
        Ok(Some(value)) => value,
        _ => String::new(),
    };

    Ok(Response::builder()
        .status(200)
        .body(Body::from(format!(
            "Username: {username}, Password: {password}"
        )))?)
}
```

## Configuration

| Key | Type | Required | Description |
|---|---|---|---|
| `USERNAME` | Environment variable | No | Read via `std::env::var`. Empty string if unset. |
| `PASSWORD` | Secret | No | Read via `fastedge::secret::get`. Empty string if unset or unavailable. |

Environment variables are set via the FastEdge app configuration. Secrets are stored encrypted and accessed through the `fastedge` crate.

## Response

```
HTTP/1.1 200 OK

Username: <USERNAME value>, Password: <PASSWORD value>
```

## Dependencies

```toml
[dependencies]
wstd = "0.6"
fastedge = "0.4"
anyhow = "1"
```

The `fastedge` crate is required for secret access. It must be added explicitly — it is not included in the base HTTP skeleton.

```toml
[lib]
crate-type = ["cdylib"]
```

## Build

```sh
cargo build --release
# Output: target/wasm32-wasip2/release/variables_and_secrets.wasm
```

## See Also

- http-base skeleton reference
- deploy skill reference (uploading the compiled `.wasm` binary)
- manage skill reference (setting environment variables and secrets on an app)
- FastEdge platform overview (secret storage model)

## Source Material

### FILE: examples/http/wasi/variables_and_secrets/src/lib.rs

```rust
use fastedge::secret;
use std::env;
use wstd::http::body::Body;
use wstd::http::{Request, Response};

#[wstd::http_server]
async fn main(_request: Request<Body>) -> anyhow::Result<Response<Body>> {
    let username = env::var("USERNAME").unwrap_or_default();
    let password = match secret::get("PASSWORD") {
        Ok(Some(value)) => value,
        _ => String::new(),
    };

    Ok(Response::builder()
        .status(200)
        .body(Body::from(format!(
            "Username: {username}, Password: {password}"
        )))?)
}
```


### FILE: examples/http/wasi/variables_and_secrets/Cargo.toml

```toml
[workspace]

[package]
name = "variables_and_secrets"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
wstd = "0.6"
fastedge = "0.4"
anyhow = "1"
```


### FILE: examples/http/wasi/variables_and_secrets/README.md

```
[← Back to examples](../../../README.md)

# Variables and Secrets (WASI)

Demonstrates reading an environment variable (`USERNAME`) and a secret (`PASSWORD`), returning both in the response body.

Environment variables are set via the FastEdge app configuration and accessed with `std::env::var`. Secrets are stored encrypted and accessed with `fastedge::secret::get` — they are never exposed in platform logs or configuration UIs.

## Configuration

| Key | Type | Required | Description |
|---|---|---|---|
| `USERNAME` | Environment variable | No | Username to include in response. Empty string if unset. |
| `PASSWORD` | Secret | No | Password to include in response. Empty string if unset or unavailable. |

## What it returns

```
HTTP/1.1 200 OK

Username: <USERNAME value>, Password: <PASSWORD value>
```

## Build

```sh
cargo build --release
# Output: target/wasm32-wasip2/release/variables_and_secrets.wasm
```

## APIs used

- `std::env::var("USERNAME").unwrap_or_default()` — read env var with fallback
- `fastedge::secret::get("PASSWORD")` — read secret by name; returns `Ok(Some(String))` on success
```
