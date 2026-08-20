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
capabilities: [geo-redirect, headers]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/geo_redirect
---

# Feature: Geo Redirect (WASI, Rust)

Redirect incoming requests to country-specific origin URLs based on the `geoip-country-code` request header injected by FastEdge. Falls back to `BASE_ORIGIN` when no per-country mapping is configured.

## When to Use

Use this feature when the app must route visitors to different upstream origins depending on their geographic location, using the `geoip-country-code` header that FastEdge injects automatically at the edge.

## Dependencies

No additions required beyond the base skeleton. `wstd` and `anyhow` are already supplied by `http-base`.

```toml
[dependencies]
wstd = "0.6"
anyhow = "1"
```

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `BASE_ORIGIN` | Yes | Fallback redirect URL (e.g. `https://example.com`). Returns 500 if unset. |
| `<COUNTRY_CODE>` | No | Per-country redirect URL keyed by 2-letter ISO country code (e.g. `US`, `DE`, `GB`). Falls back to `BASE_ORIGIN` if not set for the detected country. |

## Redirect Logic

```
geoip-country-code: DE  →  env var "DE" is set    →  302 to DE value
geoip-country-code: FR  →  env var "FR" not set   →  302 to BASE_ORIGIN
(header absent)         →  302 to BASE_ORIGIN
BASE_ORIGIN not set     →  500 Internal Server Error
```

- If the `geoip-country-code` header is absent or empty, the app goes directly to `BASE_ORIGIN` without attempting any country-code env lookup.
- If the header is present but no matching env var exists for that country code, the app falls back to `BASE_ORIGIN`.

## Key API Usage

### Read the geo header

```rust
let country_code = req
    .headers()
    .get("geoip-country-code")
    .and_then(|v| v.to_str().ok())
    .unwrap_or("")
    .to_string();
```

- `req.headers().get("geoip-country-code")` — returns `Option<&HeaderValue>`
- `.and_then(|v| v.to_str().ok())` — converts to `&str`, discards non-UTF-8 values
- `.unwrap_or("")` — treats absent or invalid header as empty string

### Two-tier origin lookup

```rust
let redirect_origin = if !country_code.is_empty() {
    env::var(&country_code).unwrap_or(base_origin)
} else {
    base_origin
};
```

- First tier: attempt `env::var(&country_code)` using the header value as the variable name.
- Second tier: if the header is empty or the env var is unset, use `base_origin` (`BASE_ORIGIN`).

### Return redirect response

```rust
Ok(Response::builder()
    .status(302)
    .header("location", &redirect_origin)
    .body(Body::empty())?)
```

- Status: `302 Found`
- `location` header: set to the resolved origin URL
- Body: empty (`Body::empty()`)

### Error response when BASE_ORIGIN is unset

```rust
return Ok(Response::builder()
    .status(500)
    .body(Body::from("BASE_ORIGIN is not set"))?);
```

## Complete Implementation

```rust
use std::env;
use wstd::http::body::Body;
use wstd::http::{Request, Response};

#[wstd::http_server]
async fn main(req: Request<Body>) -> anyhow::Result<Response<Body>> {
    let base_origin = match env::var("BASE_ORIGIN") {
        Ok(origin) => origin,
        Err(_) => {
            return Ok(Response::builder()
                .status(500)
                .body(Body::from("BASE_ORIGIN is not set"))?);
        }
    };

    let country_code = req
        .headers()
        .get("geoip-country-code")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
        .to_string();

    let redirect_origin = if !country_code.is_empty() {
        env::var(&country_code).unwrap_or(base_origin)
    } else {
        base_origin
    };

    Ok(Response::builder()
        .status(302)
        .header("location", &redirect_origin)
        .body(Body::empty())?)
}
```

## Build Output

```sh
cargo build --release
# Output: target/wasm32-wasip2/release/geo_redirect_wasi.wasm
```

## See Also

- http-base skeleton reference
- FastEdge platform overview (geoip-country-code header injection)
- deploy skill reference (uploading WASM binary and setting environment variables)

## Source Material

### FILE: examples/http/wasi/geo_redirect/src/lib.rs

```rust
/*
* Copyright 2025 G-Core Innovations SARL
*/
/*
Example WASI-HTTP app demonstrating geo-based redirects.

Reads the country code from the geoip-country-code request header
and redirects to a country-specific origin URL. Falls back to
BASE_ORIGIN when no country-specific mapping is configured.

Required configuration:
  - Environment variable: BASE_ORIGIN (fallback origin URL)
  - Environment variable: <COUNTRY_CODE> (optional per-country origin URLs, e.g. US, DE, GB)
*/

use std::env;
use wstd::http::body::Body;
use wstd::http::{Request, Response};

#[wstd::http_server]
async fn main(req: Request<Body>) -> anyhow::Result<Response<Body>> {
    let base_origin = match env::var("BASE_ORIGIN") {
        Ok(origin) => origin,
        Err(_) => {
            return Ok(Response::builder()
                .status(500)
                .body(Body::from("BASE_ORIGIN is not set"))?);
        }
    };

    let country_code = req
        .headers()
        .get("geoip-country-code")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
        .to_string();

    let redirect_origin = if !country_code.is_empty() {
        env::var(&country_code).unwrap_or(base_origin)
    } else {
        base_origin
    };

    Ok(Response::builder()
        .status(302)
        .header("location", &redirect_origin)
        .body(Body::empty())?)
}
```


### FILE: examples/http/wasi/geo_redirect/Cargo.toml

```toml
[workspace]

[package]
name = "geo_redirect_wasi"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
wstd = "0.6"
anyhow = "1"
```


### FILE: examples/http/wasi/geo_redirect/README.md

```
[← Back to examples](../../../README.md)

# Geo Redirect (WASI)

Redirects requests to country-specific origins based on the `geoip-country-code` request header. Falls back to `BASE_ORIGIN` when no country-specific mapping is configured.

Demonstrates reading request headers, reading environment variables, and returning redirect responses.

## Configuration

| Env var | Required | Description |
|---|---|---|
| `BASE_ORIGIN` | Yes | Fallback redirect URL (e.g. `https://example.com`). Returns 500 if unset. |
| `<COUNTRY_CODE>` | No | Per-country redirect URL, keyed by 2-letter country code (e.g. `DE`, `US`, `GB`). Falls back to `BASE_ORIGIN` if not set. |

## How it works

```
geoip-country-code: DE  →  env var DE is set  →  302 to DE value
geoip-country-code: FR  →  env var FR not set  →  302 to BASE_ORIGIN
(no header)             →  302 to BASE_ORIGIN
BASE_ORIGIN not set     →  500
```

## Build

```sh
cargo build --release
# Output: target/wasm32-wasip2/release/geo_redirect_wasi.wasm
```

## APIs used

- `request.headers().get("geoip-country-code")` — read geo header injected by the FastEdge edge
- `std::env::var(country_code)` — dynamic env var lookup by country code
- `Response::builder().status(302).header("location", url)` — redirect response
```
