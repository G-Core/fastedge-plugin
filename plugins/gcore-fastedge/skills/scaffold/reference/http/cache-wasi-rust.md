<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-rust
      ref: main
      commit: 6347a7c2fda0d03e66f1214db5eec041c16801b7
      updated: 2026-08-17
-->

---
type: feature
app_type: http
languages: [rust]
capabilities: [cache, outbound-http]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/cache
---

# Cache (WASI) — Rust Feature Blueprint

## When to Use

Use this blueprint when the user wants to cache upstream HTTP responses at the edge, keyed by request path and query string, to reduce origin load. Supports configurable TTL, selective purging, and transparent cache-aside forwarding.

## Dependencies

Add to `Cargo.toml` (in addition to base skeleton deps):

```toml
fastedge = "0.4"
anyhow = "1"
wstd = "0.6"
```

Crate type must be `cdylib`:

```toml
[lib]
crate-type = ["cdylib"]
```

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `ORIGIN_HOST` | Yes | Base URL of the upstream origin (e.g. `https://api.example.com`). App returns error if unset. |
| `CACHE_TTL_MS` | No | Cache TTL in milliseconds. Default: `60000` (60 s). Can be overridden per-request via `cache-ttl-ms` header. |

## Handler Signature

```rust
#[wstd::http_server]
async fn main(req: Request<Body>) -> anyhow::Result<Response<Body>>
```

The handler is `async` (WASI); cache API calls (`fastedge::cache`) are synchronous within it.

## Imports

```rust
use std::env;
use anyhow::anyhow;
use fastedge::cache;
use wstd::http::body::Body;
use wstd::http::{Client, Request, Response};
```

## Cache Key Construction

```rust
let path_and_query = req
    .uri()
    .path_and_query()
    .map(|pq| pq.as_str())
    .unwrap_or("/");

let cache_key = format!("cache:{path_and_query}");
```

Cache key format: `cache:<path>?<query>` (e.g. `cache:/data?id=1`).

## TTL Resolution (per-request override)

```rust
let ttl_ms = req.headers().get("cache-ttl-ms")
    .and_then(|v| v.to_str().ok())
    .and_then(|s| s.parse().ok())
    .unwrap_or_else(|| {
        env::var("CACHE_TTL_MS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(60_000)
    });
```

Priority: `cache-ttl-ms` request header → `CACHE_TTL_MS` env var → `60000` ms default.

## Cache API

All cache calls are synchronous and return `Result`.

### Read

```rust
cache::get(key: &str) -> Result<Option<Vec<u8>>>
```

Returns `Ok(Some(bytes))` on hit, `Ok(None)` on miss, `Err` on failure.

### Write

```rust
cache::set(key: &str, value: &[u8], ttl_ms: Option<u64>) -> Result<()>
```

- `ttl_ms`: `Some(ms)` for expiry, `None` for no expiry.
- Only call on 2xx responses.

### Purge All

```rust
cache::purge() -> Result<u64>
```

Returns count of deleted keys.

### Purge by Prefix

```rust
cache::purge_prefix(prefix: &str) -> Result<u64>
```

Deletes all keys whose cache key starts with `prefix`. Returns count of deleted keys.

### Delete Single Key

```rust
cache::delete(key: &str) -> Result<()>
```

## Cache Hit Fast-Path

```rust
if let Some(cached) = cache::get(&cache_key)? {
    return Ok(Response::builder()
        .status(200)
        .header("content-type", "application/octet-stream")
        .header("x-cache", "hit")
        .body(Body::from(cached))?);
}
```

Cache hits return immediately without forwarding to origin. Response uses `content-type: application/octet-stream` (original content-type is not stored alongside body bytes).

## Cache Miss — Origin Forwarding

```rust
let upstream_url = format!("{}{}", origin.trim_end_matches('/'), path_and_query);

let upstream_req = Request::get(&upstream_url)
    .body(Body::empty())
    .map_err(|e| anyhow!("failed to build upstream request: {e}"))?;

let upstream_resp = Client::new()
    .send(upstream_req)
    .await
    .map_err(|e| anyhow!("upstream request failed: {e}"))?;
```

### Read Upstream Body

```rust
let mut body = upstream_resp.into_body();
let body_bytes = body.contents().await?.to_vec();
```

Must call `.into_body()` before reading; `.contents().await?` buffers the full response body.

### Conditional Cache Write

```rust
if status.is_success() {
    cache::set(&cache_key, &body_bytes, Some(ttl_ms))?;
}
```

Only 2xx responses are cached. Error responses pass through without being stored.

### Replay Origin Response

```rust
let mut builder = Response::builder()
    .status(status)
    .header("x-cache", "miss");
for (k, v) in &headers {
    builder = builder.header(k, v);
}
Ok(builder.body(Body::from(body_bytes))?)
```

Origin response headers are replayed on cache miss. `x-cache: miss` header is added.

## Special Purge Routes

Handled before cache lookup and origin forwarding:

| Route | Behavior |
|---|---|
| `GET /purge` | Purges all cached keys; returns 204 |
| `GET /purge/<path_and_query>` | Purges keys with prefix `cache:/<path_and_query>`; returns 204 |
| `GET /delete/<path_and_query>` | Deletes single key `cache:/<path_and_query>`; returns 204 |

Purge all example:

```rust
if path_and_query == "/purge" {
    let deleted = cache::purge()?;
    println!("purge all: {deleted} keys removed");
    return Ok(Response::builder().status(204).body(Body::empty())?);
}
```

Purge prefix example:

```rust
if let Some(prefix) = path_and_query.strip_prefix("/purge/") {
    let prefix = format!("cache:/{prefix}");
    let deleted = cache::purge_prefix(&prefix)?;
    println!("purge prefix '{prefix}': {deleted} keys removed");
    return Ok(Response::builder().status(204).body(Body::empty())?);
}
```

Delete single key example:

```rust
if let Some(prefix) = path_and_query.strip_prefix("/delete/") {
    let prefix = format!("cache:/{prefix}");
    cache::delete(&prefix)?;
    println!("prefix '{prefix}': removed");
    return Ok(Response::builder().status(204).body(Body::empty())?);
}
```

## Request/Response Flow

```
GET /data?id=1
  → check cache key "cache:/data?id=1"
  → HIT:  return cached bytes, x-cache: hit, 200
  → MISS: forward GET to ORIGIN_HOST/data?id=1
          → 2xx: cache body with TTL, replay headers, x-cache: miss, 200
          → non-2xx: pass through without caching, x-cache: miss
```

## Error Conditions

| Condition | Behavior |
|---|---|
| `ORIGIN_HOST` not set | Returns `Err` (propagates as 500) |
| `cache::get` fails | Propagates `Err` |
| `cache::set` fails | Propagates `Err` |
| Upstream request fails | Propagates `Err` via `anyhow!` |
| Body read fails | Propagates `Err` |

## Build

```sh
cargo build --release
# Output: target/wasm32-wasip2/release/cache_wasi.wasm
```

## See Also

- fastedge::cache API reference
- http-base skeleton
- outbound-http feature blueprint
- platform-overview (environment variable configuration)
