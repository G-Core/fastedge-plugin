<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-rust
      ref: main
      commit: 6eedcca9d5c0ddd4ff79ca475965393891da2d75
      updated: 2026-09-22
-->

# CDN Cache — Rust Example

## Overview

Demonstrates cache operations in a CDN app using the proxy-wasm ABI via `fastedge::proxywasm::cache`. The cache has no named stores or handles — every operation is scoped to the calling application and addressed by key alone. This distinguishes it from the KV store, which uses named stores.

Operations are selected via the `action` query parameter. All responses are JSON. Errors return HTTP 500 with `{"error": "..."}`.

## App Type

- **App type**: CDN (proxy-wasm)
- **Language**: Rust
- **Crate type**: `cdylib`
- **Entry point**: `on_http_response_body` — operations run during the response phase

## Dependencies

```toml
proxy-wasm = "0.2"
fastedge = { path = "...", features = ["proxywasm"] }
querystring = "1.1"
serde_json = "1"
```

Feature flag `proxywasm` must be enabled on the `fastedge` crate.

## API Reference

All functions are in the `fastedge::proxywasm::cache` module.

### `cache::get`

```rust
pub fn get(key: &str) -> Result<Option<Vec<u8>>, Error>
```

Retrieves cached bytes by key.

- Returns `Ok(Some(Vec<u8>))` when the key exists.
- Returns `Ok(None)` when the key is absent.
- Returns `Err` on host error.

### `cache::set`

```rust
pub fn set(key: &str, value: &[u8], ttl_ms: Option<u64>) -> Result<(), Error>
```

Stores bytes under a key with an optional TTL.

- `ttl_ms`: milliseconds until expiry. Pass `None` for no expiry.
- Overwrites any existing value for the key.

### `cache::delete`

```rust
pub fn delete(key: &str) -> Result<(), Error>
```

Removes a key. No-op when the key is absent.

### `cache::exists`

```rust
pub fn exists(key: &str) -> Result<bool, Error>
```

Tests whether a key is present. Returns `true` if the key exists, `false` otherwise.

### `cache::incr`

```rust
pub fn incr(key: &str, delta: i64) -> Result<i64, Error>
```

Atomically increments (or decrements) a numeric counter stored under `key`.

- `delta` may be negative.
- A missing key is treated as starting at `0`.
- Returns the new value after applying `delta`.

### `cache::expire`

```rust
pub fn expire(key: &str, ttl_ms: u64) -> Result<bool, Error>
```

Sets or updates the expiry of an existing key.

- `ttl_ms`: milliseconds from now until the key expires.
- Returns `true` if the key existed and was updated, `false` if the key was absent.

### `cache::purge`

```rust
pub fn purge() -> Result<u64, Error>
```

Deletes every key owned by the calling application.

- Returns the number of keys deleted.

### `cache::purge_prefix`

```rust
pub fn purge_prefix(prefix: &str) -> Result<u64, Error>
```

Deletes all keys owned by the calling application whose names start with `prefix`.

- Returns the number of keys deleted.

## Query Parameter Interface

The example app exposes all cache operations via HTTP query parameters.

| Query string | Operation |
|---|---|
| `?action=get&key=<key>` | Read a value. `response` is `null` when absent. |
| `?action=set&key=<key>&value=<value>[&ttl=<ms>]` | Store a value. Omit `ttl` for no expiry. |
| `?action=delete&key=<key>` | Delete a key. No-op when absent. |
| `?action=exists&key=<key>` | Key membership check. |
| `?action=incr&key=<key>&delta=<i64>` | Atomic increment/decrement. Missing key starts at `0`. |
| `?action=expire&key=<key>&ttl=<ms>` | Set or update expiry. `response` is `false` when key absent. |
| `?action=purge` | Delete all keys for this app; returns count deleted. |
| `?action=purgePrefix&prefix=<prefix>` | Delete keys with prefix; returns count deleted. |

Default action when `action` is omitted: `get`.

## Response Format

Successful responses are JSON objects. Shape varies by action:

**get**
```json
{ "action": "get", "key": "<key>", "response": "<value>" | null }
```

**set**
```json
{ "action": "set", "key": "<key>", "value": "<value>", "ttlMs": <ms> | null, "response": true }
```

**delete**
```json
{ "action": "delete", "key": "<key>", "response": true }
```

**exists**
```json
{ "action": "exists", "key": "<key>", "response": true | false }
```

**incr**
```json
{ "action": "incr", "key": "<key>", "delta": <i64>, "response": <new_value> }
```

**expire**
```json
{ "action": "expire", "key": "<key>", "ttlMs": <ms>, "response": true | false }
```

**purge**
```json
{ "action": "purge", "response": <count_deleted> }
```

**purgePrefix**
```json
{ "action": "purgePrefix", "prefix": "<prefix>", "response": <count_deleted> }
```

**Error (HTTP 500)**
```json
{ "error": "<message>" }
```

## Proxy-wasm Integration

The app uses the proxy-wasm `HttpContext` trait. Key implementation details:

- Operations execute in `on_http_response_body`, triggered when `end_of_stream` is `true`.
- The request query string is read via `self.get_property(vec!["request.query"])`.
- Response headers are set in `on_http_response_headers`: removes `content-length`, sets `content-type: application/json`, sets `transfer-encoding: chunked`.
- The upstream response body is replaced entirely using `set_http_response_body`.
- Error status is set via `self.set_property(vec!["response.status"], Some(b"500"))`.
- The app pauses body accumulation (`Action::Pause`) until `end_of_stream` is received.

## Build

```sh
cargo build --release
# Output: target/wasm32-wasip1/release/cache.wasm
```

## Usage Examples

```sh
curl 'https://<your-app>/?action=set&key=hits&value=0&ttl=60000'
curl 'https://<your-app>/?action=incr&key=hits&delta=1'
curl 'https://<your-app>/?action=get&key=hits'
```

## Constraints and Behavior Notes

- Cache scope is per-application. Two apps cannot share cache entries.
- `set` with no `ttl` parameter stores the value with no expiry.
- `incr` operates atomically. The key must store a numeric value; if the key is absent it is initialized to `0` before applying `delta`.
- `expire` returns `false` (not an error) when the target key does not exist.
- `purge` and `purge_prefix` return the count of deleted keys, not an error, when no matching keys exist.
- All values are stored and retrieved as bytes (`&[u8]` / `Vec<u8>`). String conversion is the caller's responsibility.

## See Also

- CDN KV store example (key_value) — named stores, per-store handles, similar operation set
- `fastedge::proxywasm` module — proxy-wasm host service bindings
- proxy-wasm `HttpContext` trait — lifecycle hooks used by CDN apps
- FastEdge CDN app platform overview — app type selection, deployment model
