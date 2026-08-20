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
capabilities: [bloom-filter, kv-store, ip-denylist]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/bloom_filter_denylist
---

# Bloom Filter IP Denylist (WASI, Rust)

## When to Use

Use this blueprint when the user wants to block HTTP requests from IPs stored in a pre-populated bloom filter in FastEdge KV. The handler checks the client IP against a bloom filter key and returns 403 on a match, 200 otherwise. Suitable for high-throughput denylist enforcement where probabilistic false positives (over-blocking) are acceptable. Not suitable for allowlists.

## Dependencies

Add to `Cargo.toml` (beyond the base skeleton):

```toml
[dependencies]
wstd = "0.6"
fastedge = "0.4"
anyhow = "1"
serde_json = "1"
```

`[lib]` must specify `crate-type = ["cdylib"]`.

## Required Configuration

| Type | Name | Description |
|---|---|---|
| Environment variable | `DENYLIST_STORE` | KV store name holding the bloom filter |

The bloom filter key is hardcoded to `"blocked-ips"`. The handler is read-only; populate the filter out of band.

## Key APIs

### `fastedge::key_value::Store::open`

```rust
Store::open(name: &str) -> Result<Store, fastedge::key_value::Error>
```

Opens a named KV store. Errors:
- `Error::AccessDenied` — app does not have permission to access this store; return 403.
- Other variants — surface as 500.

### `store.bf_exists`

```rust
store.bf_exists(key: &str, value: &str) -> Result<bool, Error>
```

Checks bloom filter membership. Returns `Ok(true)` if `value` is (probably) in the set stored at `key`, `Ok(false)` if definitely not. False positives are possible; false negatives are not.

## Client IP Extraction

```rust
let client_ip = headers
    .get("x-real-ip")
    .or_else(|| headers.get("x-forwarded-for"))
    .and_then(|v| v.to_str().ok())
    .and_then(|v| v.split(',').next())
    .map(str::trim)
    .filter(|s| !s.is_empty());
```

- Primary header: `x-real-ip`
- Fallback header: `x-forwarded-for` (first comma-delimited token, trimmed)
- If no IP is resolvable, return 500.

## Response Logic

| Condition | Status | Body |
|---|---|---|
| `DENYLIST_STORE` not set or empty | 500 | `{"error": "DENYLIST_STORE environment variable is not configured"}` |
| Client IP not available | 500 | `{"error": "client IP not available"}` |
| Store open: `AccessDenied` | 403 | `{"error": "access denied opening denylist store"}` |
| Store open: other error | 500 | `{"error": "store open error: <msg>"}` |
| `bf_exists` error | propagated via `anyhow!` | — |
| IP matched (bloom filter hit) | 403 | `{"allowed": false, "ip": "<ip>"}` |
| IP not matched | 200 | `{"allowed": true, "ip": "<ip>"}` |

All responses use `Content-Type: application/json`.

## JSON Response Helper

```rust
fn json_response(status: u16, value: serde_json::Value) -> anyhow::Result<Response<Body>> {
    Ok(Response::builder()
        .status(status)
        .header("content-type", "application/json")
        .body(Body::from(value.to_string()))?)
}
```

Use `serde_json::json!` macro to construct response bodies inline.

## Complete Handler Structure

```rust
use std::env;

use anyhow::anyhow;
use fastedge::key_value::{Error as StoreError, Store};
use serde_json::json;
use wstd::http::body::Body;
use wstd::http::{Request, Response};

const BLOOM_KEY: &str = "blocked-ips";

#[wstd::http_server]
async fn main(req: Request<Body>) -> anyhow::Result<Response<Body>> {
    let store_name = match env::var("DENYLIST_STORE") {
        Ok(s) if !s.trim().is_empty() => s,
        _ => {
            return json_response(
                500,
                json!({ "error": "DENYLIST_STORE environment variable is not configured" }),
            );
        }
    };

    let headers = req.headers();
    let client_ip = headers
        .get("x-real-ip")
        .or_else(|| headers.get("x-forwarded-for"))
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.split(',').next())
        .map(str::trim)
        .filter(|s| !s.is_empty());

    let Some(ip) = client_ip else {
        return json_response(500, json!({ "error": "client IP not available" }));
    };

    let store = match Store::open(&store_name) {
        Ok(s) => s,
        Err(StoreError::AccessDenied) => {
            return json_response(
                403,
                json!({ "error": "access denied opening denylist store" }),
            );
        }
        Err(e) => {
            return json_response(500, json!({ "error": format!("store open error: {e}") }));
        }
    };

    let blocked = store
        .bf_exists(BLOOM_KEY, ip)
        .map_err(|e| anyhow!("bf_exists error: {e}"))?;

    if blocked {
        // Bloom filter says "maybe in set" — a small fraction of hits will be false
        // positives. Acceptable for a denylist (you over-block some legitimate users);
        // not acceptable for allowlists — use `store.get()` against a regular key instead.
        return json_response(403, json!({ "allowed": false, "ip": ip }));
    }

    json_response(200, json!({ "allowed": true, "ip": ip }))
}

fn json_response(status: u16, value: serde_json::Value) -> anyhow::Result<Response<Body>> {
    Ok(Response::builder()
        .status(status)
        .header("content-type", "application/json")
        .body(Body::from(value.to_string()))?)
}
```

## Constraints and Notes

- Bloom filters produce false positives (over-blocking of legitimate IPs). This is acceptable for denylists; for allowlists, use `store.get()` against a regular KV key instead.
- The bloom filter key `"blocked-ips"` is hardcoded. Populate it out of band before deployment.
- `DENYLIST_STORE` must be a non-empty, non-whitespace string; the guard rejects blank values explicitly.
- `bf_exists` errors propagate via `anyhow!` and result in a 500 from the runtime error handler.

## See Also

- fastedge::key_value API reference (Store, Error variants, bf_exists)
- host-services-rust reference (KV store host service documentation)
- http-base skeleton (entry point, request/response types, wstd::http_server macro)
- examples-kv-rust (general KV store usage patterns)
