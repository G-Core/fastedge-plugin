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
capabilities: [kv-store]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/key_value
---

# Feature: KV Store (HTTP Rust)

## When to Use

Use this blueprint when the user needs KV store operations in a Rust HTTP WASI app. This example demonstrates all major KV Store actions: `get`, `scan`, `zscan`, `zrange`, and `bfExists` (Bloom Filter). It parses query parameters, opens a named store, performs the requested action, and returns JSON responses.

## Dependencies to Add

These dependencies go **beyond** the base `http-base` skeleton's deps:

```toml
[dependencies]
wstd = "0.6"
anyhow = "1"
querystring = "1.1"
serde_json = "1"
```

The base skeleton already provides:
```toml
fastedge = "0.4"
```

## Files to Create

No extra files beyond `src/lib.rs` are needed. The KV store example is self-contained in a single source file.

## Files to Modify

### src/lib.rs

The example uses `[lib]` with `crate-type = ["cdylib"]` (default path `src/lib.rs`).

**Replace with:**
```rust
use std::collections::HashMap;

use anyhow::anyhow;
use fastedge::key_value::{Store, Error as StoreError};
use serde_json::json;
use wstd::http::body::Body;
use wstd::http::{Request, Response};

#[wstd::http_server]
async fn main(req: Request<Body>) -> anyhow::Result<Response<Body>> {
    let query = req.uri().query().ok_or(anyhow!("no query parameters"))?;
    let params: HashMap<&str, &str> = querystring::querify(query).into_iter().collect();

    let store_name = *params
        .get("store")
        .ok_or(anyhow!("missing param 'store'"))?;

    let action = params.get("action").copied().unwrap_or("get");

    let store = match Store::open(store_name) {
        Ok(s) => s,
        Err(StoreError::AccessDenied) => {
            return Ok(Response::builder()
                .status(403)
                .header("content-type", "application/json")
                .body(Body::from(json!({"error": "access denied"}).to_string()))?);
        }
        Err(e) => {
            return Ok(Response::builder()
                .status(500)
                .header("content-type", "application/json")
                .body(Body::from(json!({"error": format!("store open error: {e}")}).to_string()))?);
        }
    };

    let body = match action {
        "get" => handle_get(&store, &params)?,
        "scan" => handle_scan(&store, &params)?,
        "zrange" => handle_zrange(&store, &params)?,
        "zscan" => handle_zscan(&store, &params)?,
        "bfExists" => handle_bf_exists(&store, &params)?,
        _ => {
            return Ok(Response::builder()
                .status(400)
                .header("content-type", "application/json")
                .body(Body::from(json!({"error": format!("Invalid action '{action}'. Supported: get, scan, zrange, zscan, bfExists")}).to_string()))?);
        }
    };

    Ok(Response::builder()
        .status(200)
        .header("content-type", "application/json")
        .body(Body::from(body))?)
}

fn handle_get(store: &Store, params: &HashMap<&str, &str>) -> anyhow::Result<String> {
    let key = *params.get("key").ok_or(anyhow!("missing param 'key'"))?;
    match store.get(key) {
        Ok(Some(value)) => {
            let value_str = String::from_utf8_lossy(&value);
            Ok(json!({
                "store": params.get("store").unwrap_or(&""),
                "action": "get",
                "key": key,
                "response": value_str.as_ref()
            }).to_string())
        }
        Ok(None) => Ok(json!({
            "store": params.get("store").unwrap_or(&""),
            "action": "get",
            "key": key,
            "response": null
        }).to_string()),
        Err(e) => Err(anyhow!("KV get error: {e}")),
    }
}

fn handle_scan(store: &Store, params: &HashMap<&str, &str>) -> anyhow::Result<String> {
    let pattern = *params
        .get("match")
        .ok_or(anyhow!("missing param 'match'"))?;
    match store.scan(pattern) {
        Ok(keys) => Ok(json!({
            "store": params.get("store").unwrap_or(&""),
            "action": "scan",
            "match": pattern,
            "response": keys
        }).to_string()),
        Err(e) => Err(anyhow!("KV scan error: {e}")),
    }
}

fn handle_zrange(store: &Store, params: &HashMap<&str, &str>) -> anyhow::Result<String> {
    let key = *params.get("key").ok_or(anyhow!("missing param 'key'"))?;
    let min: f64 = params
        .get("min")
        .ok_or(anyhow!("missing param 'min'"))?
        .parse()
        .map_err(|_| anyhow!("invalid 'min': must be a number"))?;
    let max: f64 = params
        .get("max")
        .ok_or(anyhow!("missing param 'max'"))?
        .parse()
        .map_err(|_| anyhow!("invalid 'max': must be a number"))?;

    match store.zrange_by_score(key, min, max) {
        Ok(entries) => {
            let entries_json: Vec<serde_json::Value> = entries
                .iter()
                .map(|(value, score)| {
                    let value_str = String::from_utf8_lossy(value);
                    json!({"value": value_str.as_ref(), "score": score})
                })
                .collect();
            Ok(json!({
                "store": params.get("store").unwrap_or(&""),
                "action": "zrange",
                "key": key,
                "min": min,
                "max": max,
                "response": entries_json
            }).to_string())
        }
        Err(e) => Err(anyhow!("KV zrange error: {e}")),
    }
}

fn handle_zscan(store: &Store, params: &HashMap<&str, &str>) -> anyhow::Result<String> {
    let key = *params.get("key").ok_or(anyhow!("missing param 'key'"))?;
    let pattern = *params
        .get("match")
        .ok_or(anyhow!("missing param 'match'"))?;

    match store.zscan(key, pattern) {
        Ok(entries) => {
            let entries_json: Vec<serde_json::Value> = entries
                .iter()
                .map(|(value, score)| {
                    let value_str = String::from_utf8_lossy(value);
                    json!({"value": value_str.as_ref(), "score": score})
                })
                .collect();
            Ok(json!({
                "store": params.get("store").unwrap_or(&""),
                "action": "zscan",
                "key": key,
                "match": pattern,
                "response": entries_json
            }).to_string())
        }
        Err(e) => Err(anyhow!("KV zscan error: {e}")),
    }
}

fn handle_bf_exists(store: &Store, params: &HashMap<&str, &str>) -> anyhow::Result<String> {
    let key = *params.get("key").ok_or(anyhow!("missing param 'key'"))?;
    let item = *params
        .get("item")
        .ok_or(anyhow!("missing param 'item'"))?;

    match store.bf_exists(key, item) {
        Ok(exists) => Ok(json!({
            "store": params.get("store").unwrap_or(&""),
            "action": "bfExists",
            "key": key,
            "item": item,
            "response": exists
        }).to_string()),
        Err(e) => Err(anyhow!("KV bfExists error: {e}")),
    }
}
```

### Cargo.toml

**Full dependencies** (base skeleton plus additions):
```toml
[package]
name = "key_value_wasi"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
wstd = "0.6"
fastedge = "0.4"
anyhow = "1"
querystring = "1.1"
serde_json = "1"
```

## Query Parameters

The app accepts these query parameters:

| Parameter | Required | Description |
|-----------|----------|-------------|
| `store`   | Yes      | Name of the KV store to open |
| `action`  | No       | One of: `get`, `scan`, `zscan`, `zrange`, `bfExists` (default: `get`) |
| `key`     | Varies   | Key to access (required for `get`, `zrange`, `zscan`, `bfExists`) |
| `match`   | Varies   | Prefix match pattern, e.g. `foo*` (required for `scan`, `zscan`) |
| `min`     | Yes for `zrange` | Minimum score bound (float); no default — must be provided |
| `max`     | Yes for `zrange` | Maximum score bound (float); no default — must be provided |
| `item`    | Yes for `bfExists` | Item to check in Bloom Filter |

## KV Store API

All KV operations are on `fastedge::key_value::Store`.

| Method | Signature | Returns | Notes |
|--------|-----------|---------|-------|
| `Store::open` | `open(name: &str) -> Result<Store, StoreError>` | `Store` or `StoreError` | `StoreError::AccessDenied` → 403 JSON; other errors → 500 JSON |
| `get` | `get(key: &str) -> Result<Option<Vec<u8>>, StoreError>` | Value bytes or `None` if not found | Returns `null` in JSON for missing keys |
| `scan` | `scan(pattern: &str) -> Result<Vec<String>, StoreError>` | List of matching keys | Pattern supports wildcards (e.g. `foo*`) |
| `zrange_by_score` | `zrange_by_score(key: &str, min: f64, max: f64) -> Result<Vec<(Vec<u8>, f64)>, StoreError>` | Scored entries in range | Returns `(value_bytes, score)` tuples |
| `zscan` | `zscan(key: &str, pattern: &str) -> Result<Vec<(Vec<u8>, f64)>, StoreError>` | Scored entries matching pattern | Returns `(value_bytes, score)` tuples |
| `bf_exists` | `bf_exists(key: &str, item: &str) -> Result<bool, StoreError>` | `true`/`false` | Bloom Filter membership check |

## JSON Response Shapes

All responses use `content-type: application/json`. JSON serialization uses `serde_json::json!` macro.

**get** (found):
```json
{"store":"<name>","action":"get","key":"<key>","response":"<value>"}
```

**get** (not found):
```json
{"store":"<name>","action":"get","key":"<key>","response":null}
```

**scan**:
```json
{"store":"<name>","action":"scan","match":"<pattern>","response":["key1","key2"]}
```

**zrange**:
```json
{"store":"<name>","action":"zrange","key":"<key>","min":<f64>,"max":<f64>,"response":[{"value":"<v>","score":<f64>}]}
```

**zscan**:
```json
{"store":"<name>","action":"zscan","key":"<key>","match":"<pattern>","response":[{"value":"<v>","score":<f64>}]}
```

**bfExists**:
```json
{"store":"<name>","action":"bfExists","key":"<key>","item":"<item>","response":true}
```

**Error (invalid action)**:
```json
HTTP 400 — {"error":"Invalid action '<action>'. Supported: get, scan, zrange, zscan, bfExists"}
```

**Error (store access denied)**:
```json
HTTP 403 — {"error":"access denied"}
```

**Error (store open failure)**:
```json
HTTP 500 — {"error":"store open error: <message>"}
```

**Error (missing/invalid params)**:
Propagated as `anyhow::Error` from handler functions; results in a 500-class response via the WASI HTTP runtime unless caught upstream.

## Key Patterns

- **`#[wstd::http_server]`** attribute macro for async HTTP app entry point (WASI)
- **`async fn main`** — entry function is async; use `.await` where needed
- **`fastedge::key_value::{Store, Error as StoreError}`** for KV operations
- **`querystring::querify`** for query parameter parsing into `HashMap<&str, &str>`
- **`serde_json::json!`** macro for all JSON response construction — no manual `format!` string building
- **`anyhow::Result`** for error propagation; `anyhow!("...")` for ad-hoc errors
- **`String::from_utf8_lossy`** + `.as_ref()` for converting `Vec<u8>` values to display strings compatible with `serde_json`
- All error responses (400, 403, 500) use JSON body with `{"error": "..."}` shape and `content-type: application/json` header
- `StoreError::AccessDenied` is explicitly matched on `Store::open` to return 403

## Build Notes

Standard Rust WASI build: `cargo build --release --target wasm32-wasip1`

Requires `.cargo/config.toml`:
```toml
[build]
target = "wasm32-wasip1"
```

## See Also

- fastedge-sdk-rust key_value module documentation
- http-base skeleton reference
- wstd HTTP server documentation

## Source Material

### FILE: examples/http/wasi/key_value/src/lib.rs

```rust
/*
* Copyright 2025 G-Core Innovations SARL
*/
/*
Example app demonstrating KV Store operations via the WASI-HTTP interface.

Supports all KV Store operations via query parameters:
  ?store=<name>&action=get&key=<key>
  ?store=<name>&action=scan&match=<pattern>
  ?store=<name>&action=zrange&key=<key>&min=<f64>&max=<f64>
  ?store=<name>&action=zscan&key=<key>&match=<pattern>
  ?store=<name>&action=bfExists&key=<key>&item=<item>

Defaults to action=get if not specified.
*/

use std::collections::HashMap;

use anyhow::anyhow;
use fastedge::key_value::{Store, Error as StoreError};
use serde_json::json;
use wstd::http::body::Body;
use wstd::http::{Request, Response};

#[wstd::http_server]
async fn main(req: Request<Body>) -> anyhow::Result<Response<Body>> {
    let query = req.uri().query().ok_or(anyhow!("no query parameters"))?;
    let params: HashMap<&str, &str> = querystring::querify(query).into_iter().collect();

    let store_name = *params
        .get("store")
        .ok_or(anyhow!("missing param 'store'"))?;

    let action = params.get("action").copied().unwrap_or("get");

    let store = match Store::open(store_name) {
        Ok(s) => s,
        Err(StoreError::AccessDenied) => {
            return Ok(Response::builder()
                .status(403)
                .header("content-type", "application/json")
                .body(Body::from(json!({"error": "access denied"}).to_string()))?);
        }
        Err(e) => {
            return Ok(Response::builder()
                .status(500)
                .header("content-type", "application/json")
                .body(Body::from(json!({"error": format!("store open error: {e}")}).to_string()))?);
        }
    };

    let body = match action {
        "get" => handle_get(&store, &params)?,
        "scan" => handle_scan(&store, &params)?,
        "zrange" => handle_zrange(&store, &params)?,
        "zscan" => handle_zscan(&store, &params)?,
        "bfExists" => handle_bf_exists(&store, &params)?,
        _ => {
            return Ok(Response::builder()
                .status(400)
                .header("content-type", "application/json")
                .body(Body::from(json!({"error": format!("Invalid action '{action}'. Supported: get, scan, zrange, zscan, bfExists")}).to_string()))?);
        }
    };

    Ok(Response::builder()
        .status(200)
        .header("content-type", "application/json")
        .body(Body::from(body))?)
}

fn handle_get(store: &Store, params: &HashMap<&str, &str>) -> anyhow::Result<String> {
    let key = *params.get("key").ok_or(anyhow!("missing param 'key'"))?;
    match store.get(key) {
        Ok(Some(value)) => {
            let value_str = String::from_utf8_lossy(&value);
            Ok(json!({
                "store": params.get("store").unwrap_or(&""),
                "action": "get",
                "key": key,
                "response": value_str.as_ref()
            }).to_string())
        }
        Ok(None) => Ok(json!({
            "store": params.get("store").unwrap_or(&""),
            "action": "get",
            "key": key,
            "response": null
        }).to_string()),
        Err(e) => Err(anyhow!("KV get error: {e}")),
    }
}

fn handle_scan(store: &Store, params: &HashMap<&str, &str>) -> anyhow::Result<String> {
    let pattern = *params
        .get("match")
        .ok_or(anyhow!("missing param 'match'"))?;
    match store.scan(pattern) {
        Ok(keys) => Ok(json!({
            "store": params.get("store").unwrap_or(&""),
            "action": "scan",
            "match": pattern,
            "response": keys
        }).to_string()),
        Err(e) => Err(anyhow!("KV scan error: {e}")),
    }
}

fn handle_zrange(store: &Store, params: &HashMap<&str, &str>) -> anyhow::Result<String> {
    let key = *params.get("key").ok_or(anyhow!("missing param 'key'"))?;
    let min: f64 = params
        .get("min")
        .ok_or(anyhow!("missing param 'min'"))?
        .parse()
        .map_err(|_| anyhow!("invalid 'min': must be a number"))?;
    let max: f64 = params
        .get("max")
        .ok_or(anyhow!("missing param 'max'"))?
        .parse()
        .map_err(|_| anyhow!("invalid 'max': must be a number"))?;

    match store.zrange_by_score(key, min, max) {
        Ok(entries) => {
            let entries_json: Vec<serde_json::Value> = entries
                .iter()
                .map(|(value, score)| {
                    let value_str = String::from_utf8_lossy(value);
                    json!({"value": value_str.as_ref(), "score": score})
                })
                .collect();
            Ok(json!({
                "store": params.get("store").unwrap_or(&""),
                "action": "zrange",
                "key": key,
                "min": min,
                "max": max,
                "response": entries_json
            }).to_string())
        }
        Err(e) => Err(anyhow!("KV zrange error: {e}")),
    }
}

fn handle_zscan(store: &Store, params: &HashMap<&str, &str>) -> anyhow::Result<String> {
    let key = *params.get("key").ok_or(anyhow!("missing param 'key'"))?;
    let pattern = *params
        .get("match")
        .ok_or(anyhow!("missing param 'match'"))?;

    match store.zscan(key, pattern) {
        Ok(entries) => {
            let entries_json: Vec<serde_json::Value> = entries
                .iter()
                .map(|(value, score)| {
                    let value_str = String::from_utf8_lossy(value);
                    json!({"value": value_str.as_ref(), "score": score})
                })
                .collect();
            Ok(json!({
                "store": params.get("store").unwrap_or(&""),
                "action": "zscan",
                "key": key,
                "match": pattern,
                "response": entries_json
            }).to_string())
        }
        Err(e) => Err(anyhow!("KV zscan error: {e}")),
    }
}

fn handle_bf_exists(store: &Store, params: &HashMap<&str, &str>) -> anyhow::Result<String> {
    let key = *params.get("key").ok_or(anyhow!("missing param 'key'"))?;
    let item = *params
        .get("item")
        .ok_or(anyhow!("missing param 'item'"))?;

    match store.bf_exists(key, item) {
        Ok(exists) => Ok(json!({
            "store": params.get("store").unwrap_or(&""),
            "action": "bfExists",
            "key": key,
            "item": item,
            "response": exists
        }).to_string()),
        Err(e) => Err(anyhow!("KV bfExists error: {e}")),
    }
}
```

### FILE: examples/http/wasi/key_value/Cargo.toml

```toml
[workspace]

[package]
name = "key_value_wasi"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
wstd = "0.6"
fastedge = "0.4"
anyhow = "1"
querystring = "1.1"
serde_json = "1"
```
