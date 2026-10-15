<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-rust
      ref: v0.4.5
      commit: e7f446a4b40b791b932ab36b2c7a0c85fd24104d
      updated: 2026-10-14
-->

```yaml
type: feature
app_type: cdn
languages: [rust]
capabilities: [cache]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/cache
```

# CDN Cache — Rust

## When to Use

Use this blueprint when you need app-scoped, TTL-based key/value storage at the CDN layer: counters, rate limiting, short-lived memoisation, or any per-request state that must survive across requests but expire automatically.

Important scope constraints:
- Cache is per PoP, not global or account-wide. Limits and counters increment independently on each PoP.
- This is not HTTP response caching (`Cache-Control`); that is the `cache-control` blueprint.
- This is not read-mostly named stores with open/close handles; that is the `kv-store` blueprint.

## App Type

- **App type**: CDN (proxy-wasm)
- **Language**: Rust
- **Crate type**: `cdylib`
- **Entry point**: `on_http_response_body` — all cache operations run during the response phase

## Dependencies

Add to the base skeleton's `Cargo.toml`:

```toml
fastedge = { version = "0.4", features = ["proxywasm"] }
querystring = "1.1"
serde_json = "1"
```

The base skeleton already provides `proxy-wasm = "0.2"`. The `proxywasm` feature flag on the `fastedge` crate is required to access `fastedge::proxywasm::cache`.

## API Reference

All functions are free functions in `fastedge::proxywasm::cache`. There is no named store, no handle, and no `open()` call. Every key is scoped to the calling application and is local to the PoP — values are not replicated across PoPs.

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

- `ttl_ms`: milliseconds until expiry.
- Pass `None` to use the host default TTL (~4 days). Passing `Some(0)` behaves identically — the SDK sends `0` for `None`. The host clamps every `set` to a deployment ceiling (default ~4 days), whether or not a TTL is provided. This behaviour was measured on HTTP apps and is not yet verified for CDN (proxy-wasm) apps.
- Handlers should reject `ttl=0` from callers rather than silently falling back to the host default.
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

Atomically increments or decrements a numeric counter stored under `key`.

- `delta` may be negative.
- A missing key is treated as starting at `0`.
- Returns the new value after applying `delta`.
- **TTL note**: `incr` sets no TTL and does not index the key in the same way as `set`. As a result, `purge` and `purge_prefix` may miss keys created only via `incr`. Call `expire` explicitly after `incr` to arm a TTL. See the FastEdge storage platform reference for the `expire` pattern.

### `cache::expire`

```rust
pub fn expire(key: &str, ttl_ms: u64) -> Result<bool, Error>
```

Sets or updates the expiry of an existing key.

- `ttl_ms`: milliseconds from now until the key expires.
- Returns `true` if the key existed and was updated, `false` if the key was absent (not an error).

### `cache::purge`

```rust
pub fn purge() -> Result<u64, Error>
```

Deletes every key owned by the calling application that is indexed (see `incr` TTL note above).

- Returns the number of keys deleted (not an error when no keys exist).

### `cache::purge_prefix`

```rust
pub fn purge_prefix(prefix: &str) -> Result<u64, Error>
```

Deletes all indexed keys owned by the calling application whose names start with `prefix`.

- Returns the number of keys deleted (not an error when no matching keys exist).

## Proxy-wasm Integration

The app implements the proxy-wasm `HttpContext` trait. Cache operations execute in the response phase.

### Response Header Hook

```rust
fn on_http_response_headers(&mut self, _: usize, _: bool) -> Action {
    self.set_http_response_header("content-length", None);
    self.set_http_response_header("content-type", Some("application/json"));
    self.set_http_response_header("transfer-encoding", Some("chunked"));
    Action::Continue
}
```

**Header removal pitfall**: On FastEdge CDN, passing `None` to `set_http_response_header` sets the header to an empty string rather than removing it. Code checking for a header's absence must treat both a missing value and an empty string as absent.

### Response Body Hook

```rust
fn on_http_response_body(&mut self, body_size: usize, end_of_stream: bool) -> Action {
    if !end_of_stream {
        return Action::Pause;
    }
    // dispatch on query params, run cache operation, replace body
    self.set_http_response_body(0, body_size, result_bytes);
    Action::Continue
}
```

- Return `Action::Pause` until `end_of_stream` is `true` to accumulate the full upstream body.
- Replace the upstream response body entirely with `set_http_response_body(0, body_size, bytes)`.

### Query Parameter Dispatch

Read the request query string and parse it:

```rust
let query = self
    .get_property(vec!["request.query"])
    .and_then(|bytes| String::from_utf8(bytes).ok())
    .unwrap_or_default();

let params: HashMap<&str, &str> = querystring::querify(&query).into_iter().collect();
let action = params.get("action").copied().unwrap_or("get");

let result = match action {
    "get"         => self.handle_get(&params),
    "set"         => self.handle_set(&params),
    "delete"      => self.handle_delete(&params),
    "exists"      => self.handle_exists(&params),
    "incr"        => self.handle_incr(&params),
    "expire"      => self.handle_expire(&params),
    "purge"       => self.handle_purge(),
    "purgePrefix" => self.handle_purge_prefix(&params),
    _             => Err(format!("Invalid action '{}'...", action)),
};
```

**Security warning — demo pattern only**: The query-string dispatcher exposes mutating actions (`set`, `delete`, `incr`, `expire`, `purge`, `purgePrefix`) to any client without authentication. Real apps must gate those actions behind authorization or a trusted route.

### Per-Action Handler Shape

Each action is implemented as a method returning `Result<String, String>` — either the JSON response body or an error message string:

```rust
fn handle_get(&self, params: &HashMap<&str, &str>) -> Result<String, String> {
    let key = *params.get("key").ok_or("Missing required param 'key' for 'get' action")?;
    match cache::get(key) {
        Ok(Some(value)) => Ok(json!({ "action": "get", "key": key, "response": String::from_utf8_lossy(&value).as_ref() }).to_string()),
        Ok(None)        => Ok(json!({ "action": "get", "key": key, "response": null }).to_string()),
        Err(e)          => Err(format!("Cache get error: {}", e)),
    }
}
```

Use `serde_json::json!` macro for all JSON response construction.

### Error Handling

```rust
fn send_error(&self, msg: &str, body_size: usize) {
    self.set_property(vec!["response.status"], Some(b"500"));
    let error_body = json!({"error": msg}).to_string();
    self.set_http_response_body(0, body_size, error_body.as_bytes());
}
```

**Advisory status**: `response.status` is set inside `on_http_response_body`, after the response headers have already been sent to the client. The origin's HTTP status code reaches the client unchanged. The JSON `{"error": "..."}` body is the real error signal for callers.

## Query Parameter Interface

| Query string | Operation |
|---|---|
| `?action=get&key=<key>` | Read a value. `response` is `null` when absent. |
| `?action=set&key=<key>&value=<value>[&ttl=<ms>]` | Store a value. Omit `ttl` to use host default TTL. Do not pass `ttl=0`. |
| `?action=delete&key=<key>` | Delete a key. No-op when absent. |
| `?action=exists&key=<key>` | Key membership check. |
| `?action=incr&key=<key>&delta=<i64>` | Atomic increment/decrement. Missing key starts at `0`. |
| `?action=expire&key=<key>&ttl=<ms>` | Set or update expiry. `response` is `false` when key absent. |
| `?action=purge` | Delete all indexed keys for this app; returns count deleted. |
| `?action=purgePrefix&prefix=<prefix>` | Delete indexed keys with prefix; returns count deleted. |

Default action when `action` is omitted: `get`.

## Response Format

All successful responses are JSON. All error responses are HTTP 500 with a JSON body.

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

**Error (HTTP 500 advisory — see error handling note)**
```json
{ "error": "<message>" }
```

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

- Cache scope is per-application and per-PoP. Two apps cannot share cache entries. Counters and limits are not global.
- `set` with no `ttl` parameter uses the host default TTL (~4 days). The host clamps all TTLs to a deployment ceiling. `ttl=0` behaves the same as omitting `ttl`; callers should treat `0` as invalid.
- `incr` operates atomically. The key must store a numeric value; if absent it is initialized to `0`. `incr` sets no TTL — call `expire` explicitly to arm one.
- `purge` and `purge_prefix` only affect indexed keys. Keys created solely via `incr` (without a subsequent `set` or `expire`) may be missed.
- `expire` returns `false` (not an error) when the target key does not exist.
- `purge` and `purge_prefix` return the count of deleted keys, not an error, when no matching keys exist.
- All values are stored and retrieved as bytes (`&[u8]` / `Vec<u8>`). String conversion is the caller's responsibility.
- The host default TTL behaviour (~4 days, clamped) was measured on HTTP apps and is not yet verified for CDN (proxy-wasm) apps.
- On FastEdge CDN, `set_http_response_header("content-length", None)` sets the header to an empty string, not removes it. Treat empty string and missing as equivalent when checking header absence.
- `response.status` set in `on_http_response_body` is advisory. The origin status is what the client receives.

## See Also

- FastEdge storage platform reference — `expire` pattern for `incr` keys, TTL clamping details
- CDN KV store blueprint (`kv-store`) — named stores, per-store handles, read-mostly workloads
- CDN cache-control blueprint — HTTP response caching via `Cache-Control` headers
- `fastedge::proxywasm` module — all proxy-wasm host service bindings
- proxy-wasm `HttpContext` trait — full lifecycle hook reference
- FastEdge CDN app platform overview — app type selection, deployment model, PoP topology
