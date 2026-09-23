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
app_type: cdn
languages: [rust]
capabilities: [kv-store]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/key_value
---

# KV Store — CDN (Rust)

## When to Use

Use this blueprint when a CDN app needs to query a key-value store at the edge for data lookups, sorted sets, bloom filter membership checks, or pattern scanning — replacing or augmenting the upstream response body with KV data.

## Pattern Overview

CDN hook pattern: intercept the upstream response via `on_http_response_headers` and `on_http_response_body`. Parse query parameters from the incoming request to determine the store name and operation. Open the store, execute the operation, and replace the response body with a JSON result.

## Dependencies

```toml
[dependencies]
proxy-wasm = "0.2"
fastedge = { version = "0.4", features = ["proxywasm"] }
querystring = "1.1"
serde_json = "1"
```

Crate type must be `cdylib`.

## Imports

```rust
use fastedge::proxywasm::key_value::Store;
use proxy_wasm::traits::*;
use proxy_wasm::types::*;
use serde_json::json;
use std::collections::HashMap;
```

## Entry Point

```rust
proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Info);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(KvStoreRoot) });
}}
```

## Context Structs

```rust
struct KvStoreRoot;
impl Context for KvStoreRoot {}

impl RootContext for KvStoreRoot {
    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }
    fn create_http_context(&self, _: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(KvStoreContext))
    }
}

struct KvStoreContext;
impl Context for KvStoreContext {}
```

## Response Hook Implementation

### `on_http_response_headers`

Prepares headers for body replacement. Must run before body manipulation.

```rust
fn on_http_response_headers(&mut self, _: usize, _: bool) -> Action {
    self.set_http_response_header("content-length", None);          // remove — body size will change
    self.set_http_response_header("content-type", Some("application/json"));
    self.set_http_response_header("transfer-encoding", Some("chunked"));
    Action::Continue
}
```

**Required**: Remove `content-length` before replacing the body. Set `transfer-encoding: chunked`.

### `on_http_response_body`

Buffer full body before processing (`end_of_stream` guard). Parse query params, open store, dispatch action, replace body.

```rust
fn on_http_response_body(&mut self, body_size: usize, end_of_stream: bool) -> Action {
    if !end_of_stream {
        return Action::Pause;   // buffer until complete
    }
    // parse query, open store, dispatch, replace body
    Action::Continue
}
```

**Pattern**: Return `Action::Pause` until `end_of_stream` is `true`, then process.

## Query Parameter Parsing

Query string is retrieved from the request property path `["request.query"]` (dot-notation single string).

```rust
let query = self
    .get_property(vec!["request.query"])
    .and_then(|bytes| String::from_utf8(bytes).ok())
    .unwrap_or_default();

let params: HashMap<&str, &str> = querystring::querify(&query).into_iter().collect();
```

**Required query parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `store`   | Yes      | KV store name to open |
| `action`  | No       | Operation to perform; defaults to `get` |
| `key`     | Action-dependent | Key to operate on |
| `match`   | For `scan`, `zscan` | Glob/pattern string |
| `min`     | For `zrange` | Minimum score (f64) |
| `max`     | For `zrange` | Maximum score (f64) |
| `item`    | For `bfExists` | Item to check in bloom filter |

## Store API

### `Store::open`

```rust
Store::open(name: &str) -> Result<Store, Error>
```

Opens a named KV store. Returns `Err` if the store cannot be opened. The store name must match a store configured for the app.

### `store.get`

```rust
store.get(key: &str) -> Result<Option<Vec<u8>>, Error>
```

Retrieves a single value by key. Returns `Ok(None)` if the key does not exist.

### `store.scan`

```rust
store.scan(pattern: &str) -> Result<Vec<String>, Error>
```

Returns all keys matching the given glob pattern.

### `store.zrange_by_score`

```rust
store.zrange_by_score(key: &str, min: f64, max: f64) -> Result<Vec<(Vec<u8>, f64)>, Error>
```

Returns entries from a sorted set where the score falls within `[min, max]`. Each entry is a `(value_bytes, score)` tuple.

### `store.zscan`

```rust
store.zscan(key: &str, pattern: &str) -> Result<Vec<(Vec<u8>, f64)>, Error>
```

Returns entries from a sorted set whose values match the given pattern. Each entry is a `(value_bytes, score)` tuple.

### `store.bf_exists`

```rust
store.bf_exists(key: &str, item: &str) -> Result<bool, Error>
```

Checks membership in a bloom filter stored at `key`. Returns `Ok(true)` if the item is probably present, `Ok(false)` if definitely absent.

## Action Dispatch

```rust
let result = match action {
    "get"      => self.handle_get(&store, &params),
    "scan"     => self.handle_scan(&store, &params),
    "zrange"   => self.handle_zrange(&store, &params),
    "zscan"    => self.handle_zscan(&store, &params),
    "bfExists" => self.handle_bf_exists(&store, &params),
    _          => Err(format!(
        "Invalid action '{}'. Supported: get, scan, zrange, zscan, bfExists",
        action
    )),
};
```

Default action when `action` param is absent: `get`.

## JSON Response Format

All successful responses use `serde_json::json!` and include `store`, `action`, and `response` fields. Action-specific fields are also included.

**get (found):**
```json
{ "store": "<name>", "action": "get", "key": "<key>", "response": "<value>" }
```

**get (not found):**
```json
{ "store": "<name>", "action": "get", "key": "<key>", "response": null }
```

**scan:**
```json
{ "store": "<name>", "action": "scan", "match": "<pattern>", "response": ["key1", "key2"] }
```

**zrange:**
```json
{ "store": "<name>", "action": "zrange", "key": "<key>", "min": 0.0, "max": 10.0, "response": [{"value": "<v>", "score": 1.5}] }
```

**zscan:**
```json
{ "store": "<name>", "action": "zscan", "key": "<key>", "match": "<pattern>", "response": [{"value": "<v>", "score": 2.0}] }
```

**bfExists:**
```json
{ "store": "<name>", "action": "bfExists", "key": "<key>", "item": "<item>", "response": true }
```

**Error:**
```json
{ "error": "<message>" }
```

## Body Replacement

```rust
self.set_http_response_body(0, body_size, body.as_bytes());
```

Replaces the full upstream response body. First argument is offset (always `0`), second is the number of bytes to replace (pass `body_size` to replace all), third is the new content.

## Error Handling

Errors are logged via `println!` and returned as `{"error": "<message>"}` JSON. Response status is set to `500` via the `response.status` property (dot-notation single string).

```rust
fn send_error(&self, msg: &str, body_size: usize) {
    println!("{}", msg);
    self.set_property(vec!["response.status"], Some(b"500"));
    let error_body = json!({"error": msg}).to_string();
    self.set_http_response_body(0, body_size, error_body.as_bytes());
}
```

**Error conditions:**

| Condition | Message |
|-----------|---------|
| No query string | `"App must be called with query parameters"` |
| Missing `store` param | `"Missing required param 'store'"` |
| Store open failure | `"Failed to open KvStore '<name>': <err>"` |
| Missing `key` for `get` | `"Missing required param 'key' for 'get' action"` |
| Missing `match` for `scan` | `"Missing required param 'match' for 'scan' action"` |
| Missing `key` for `zrange` | `"Missing required param 'key' for 'zrange' action"` |
| Missing `min` for `zrange` | `"Missing required param 'min' for 'zrange' action"` |
| Missing `max` for `zrange` | `"Missing required param 'max' for 'zrange' action"` |
| Non-numeric `min`/`max` | `"Invalid 'min' value: must be a number"` / `"Invalid 'max' value: must be a number"` |
| Missing `key` for `zscan` | `"Missing required param 'key' for 'zscan' action"` |
| Missing `match` for `zscan` | `"Missing required param 'match' for 'zscan' action"` |
| Missing `key` for `bfExists` | `"Missing required param 'key' for 'bfExists' action"` |
| Missing `item` for `bfExists` | `"Missing required param 'item' for 'bfExists' action"` |
| KV get failure | `"KV get error: <err>"` |
| KV scan failure | `"KV scan error: <err>"` |
| KV zrange failure | `"KV zrange error: <err>"` |
| KV zscan failure | `"KV zscan error: <err>"` |
| KV bfExists failure | `"KV bfExists error: <err>"` |
| Unknown action | `"Invalid action '<a>'. Supported: get, scan, zrange, zscan, bfExists"` |

## Constraints

- `Vec<u8>` values from `get`, `zrange`, and `zscan` are decoded with `String::from_utf8_lossy` for JSON serialization. Non-UTF-8 bytes are replaced with the Unicode replacement character.
- `min` and `max` for `zrange` must be parseable as `f64`; any non-numeric string returns an error.
- The store name must correspond to a KV store provisioned and bound to the FastEdge app. Attempting to open an unbound store returns an error.
- `send_error` uses `println!` for logging (not `proxy_wasm::hostcalls::log`).
- Property paths use dot-notation single strings: `"request.query"` and `"response.status"` (not separate vector elements).

## See Also

- fastedge::proxywasm::key_value module (Store type and all operation signatures)
- proxy-wasm HttpContext trait (on_http_response_headers, on_http_response_body, set_http_response_body)
- cdn-base skeleton (RootContext and HttpContext wiring)
- platform-overview reference (KV store provisioning and binding)

## Source Material

### FILE: examples/cdn/key_value/src/lib.rs

```rust
/*
* Copyright 2025 G-Core Innovations SARL
*/
/*
Example CDN app demonstrating KV Store operations via the proxy-wasm interface.

Supports all KV Store operations via query parameters:
  ?store=<name>&action=get&key=<key>
  ?store=<name>&action=scan&match=<pattern>
  ?store=<name>&action=zrange&key=<key>&min=<f64>&max=<f64>
  ?store=<name>&action=zscan&key=<key>&match=<pattern>
  ?store=<name>&action=bfExists&key=<key>&item=<item>

Defaults to action=get if not specified.
*/

use fastedge::proxywasm::key_value::Store;
use proxy_wasm::traits::*;
use proxy_wasm::types::*;
use serde_json::json;
use std::collections::HashMap;

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Info);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(KvStoreRoot) });
}}

struct KvStoreRoot;

impl Context for KvStoreRoot {}

impl RootContext for KvStoreRoot {
    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }

    fn create_http_context(&self, _: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(KvStoreContext))
    }
}

struct KvStoreContext;

impl Context for KvStoreContext {}

impl HttpContext for KvStoreContext {
    fn on_http_response_headers(&mut self, _: usize, _: bool) -> Action {
        // Remove content-length since we replace the body
        self.set_http_response_header("content-length", None);
        self.set_http_response_header("content-type", Some("application/json"));
        self.set_http_response_header("transfer-encoding", Some("chunked"));
        Action::Continue
    }

    fn on_http_response_body(&mut self, body_size: usize, end_of_stream: bool) -> Action {
        if !end_of_stream {
            return Action::Pause;
        }

        let query = self
            .get_property(vec!["request.query"])
            .and_then(|bytes| String::from_utf8(bytes).ok())
            .unwrap_or_default();

        if query.is_empty() {
            self.send_error("App must be called with query parameters", body_size);
            return Action::Continue;
        }

        let params: HashMap<&str, &str> = querystring::querify(&query).into_iter().collect();

        let Some(store_name) = params.get("store") else {
            self.send_error("Missing required param 'store'", body_size);
            return Action::Continue;
        };

        let action = params.get("action").copied().unwrap_or("get");

        let store = match Store::open(store_name) {
            Ok(s) => s,
            Err(e) => {
                self.send_error(&format!("Failed to open KvStore '{}': {}", store_name, e), body_size);
                return Action::Continue;
            }
        };

        let result = match action {
            "get" => self.handle_get(&store, &params),
            "scan" => self.handle_scan(&store, &params),
            "zrange" => self.handle_zrange(&store, &params),
            "zscan" => self.handle_zscan(&store, &params),
            "bfExists" => self.handle_bf_exists(&store, &params),
            _ => Err(format!(
                "Invalid action '{}'. Supported: get, scan, zrange, zscan, bfExists",
                action
            )),
        };

        let body = match result {
            Ok(json) => json,
            Err(msg) => {
                self.send_error(&msg, body_size);
                return Action::Continue;
            }
        };

        self.set_http_response_body(0, body_size, body.as_bytes());

        Action::Continue
    }
}

impl KvStoreContext {
    fn handle_get(&self, store: &Store, params: &HashMap<&str, &str>) -> Result<String, String> {
        let key = *params.get("key").ok_or("Missing required param 'key' for 'get' action")?;
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
            Err(e) => Err(format!("KV get error: {}", e)),
        }
    }

    fn handle_scan(&self, store: &Store, params: &HashMap<&str, &str>) -> Result<String, String> {
        let pattern = *params.get("match").ok_or("Missing required param 'match' for 'scan' action")?;
        match store.scan(pattern) {
            Ok(keys) => Ok(json!({
                "store": params.get("store").unwrap_or(&""),
                "action": "scan",
                "match": pattern,
                "response": keys
            }).to_string()),
            Err(e) => Err(format!("KV scan error: {}", e)),
        }
    }

    fn handle_zrange(&self, store: &Store, params: &HashMap<&str, &str>) -> Result<String, String> {
        let key = *params.get("key").ok_or("Missing required param 'key' for 'zrange' action")?;
        let min: f64 = params
            .get("min")
            .ok_or("Missing required param 'min' for 'zrange' action")?
            .parse()
            .map_err(|_| "Invalid 'min' value: must be a number".to_string())?;
        let max: f64 = params
            .get("max")
            .ok_or("Missing required param 'max' for 'zrange' action")?
            .parse()
            .map_err(|_| "Invalid 'max' value: must be a number".to_string())?;

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
            Err(e) => Err(format!("KV zrange error: {}", e)),
        }
    }

    fn handle_zscan(&self, store: &Store, params: &HashMap<&str, &str>) -> Result<String, String> {
        let key = *params.get("key").ok_or("Missing required param 'key' for 'zscan' action")?;
        let pattern = *params.get("match").ok_or("Missing required param 'match' for 'zscan' action")?;

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
            Err(e) => Err(format!("KV zscan error: {}", e)),
        }
    }

    fn handle_bf_exists(&self, store: &Store, params: &HashMap<&str, &str>) -> Result<String, String> {
        let key = *params.get("key").ok_or("Missing required param 'key' for 'bfExists' action")?;
        let item = *params.get("item").ok_or("Missing required param 'item' for 'bfExists' action")?;

        match store.bf_exists(key, item) {
            Ok(exists) => Ok(json!({
                "store": params.get("store").unwrap_or(&""),
                "action": "bfExists",
                "key": key,
                "item": item,
                "response": exists
            }).to_string()),
            Err(e) => Err(format!("KV bfExists error: {}", e)),
        }
    }

    fn send_error(&self, msg: &str, body_size: usize) {
        println!("{}", msg);
        self.set_property(
            vec!["response.status"],
            Some(b"500"),
        );
        let error_body = json!({"error": msg}).to_string();
        self.set_http_response_body(0, body_size, error_body.as_bytes());
    }
}
```


### FILE: examples/cdn/key_value/Cargo.toml

```toml
[workspace]

[package]
name = "key_value"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
proxy-wasm = "0.2"
fastedge = { version = "0.4", features = ["proxywasm"] }
querystring = "1.1"
serde_json = "1"
```


### FILE: examples/cdn/key_value/README.md

```
[← Back to examples](../../README.md)

# Key Value (CDN)

This example shows how to read and write data from a FastEdge KV store from a CDN app.
It intercepts the HTTP response, reads the request query string, and executes a KV operation against a named store.

## What it does

The app supports the following actions:

- `get` — fetch one key
- `scan` — list keys matching a pattern
- `zrange` — read sorted-set entries by score range
- `zscan` — list sorted-set entries matching a pattern
- `bfExists` — check whether a Bloom filter contains an item

The request must include at least:

- `store=<name>` — KV store name
- `action=<operation>` — optional, defaults to `get`

For each action, the app validates required parameters and returns a JSON response body.

## Supported query examples

### Get a key

```text
?store=my_store&action=get&key=user:42
```

### List keys by pattern

```text
?store=my_store&action=scan&match=user:*
```

### Read a sorted set by score range

```text
?store=my_store&action=zrange&key=leaderboard&min=0&max=100
```

### Search sorted-set members by pattern

```text
?store=my_store&action=zscan&key=leaderboard&match=user:*
```

### Check a Bloom filter item

```text
?store=my_store&action=bfExists&key=visitors&item=alice@example.com
```

## Build

```sh
cargo build --release
# Output: target/wasm32-wasip1/release/key_value.wasm
```

This example is a CDN app, so it targets `wasm32-wasip1`.

## Response format

The app replaces the response body with JSON and sets `content-type: application/json`.
A successful response looks like this:

```json
{
  "store": "my_store",
  "action": "get",
  "key": "user:42",
  "response": "Alice"
}
```

If a required parameter is missing or the KV operation fails, the app responds with an error payload:

```json
{
  "error": "Missing required param 'key' for 'get' action"
}
```

## Notes

- The app requires query parameters to run.
- If `action` is omitted, it defaults to `get`.
- The code uses `fastedge::proxywasm::key_value::Store` and `proxy_wasm` lifecycle hooks to operate on the KV store.
```
