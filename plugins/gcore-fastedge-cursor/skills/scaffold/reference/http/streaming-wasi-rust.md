<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-rust
      ref: main
      commit: 6347a7c2fda0d03e66f1214db5eec041c16801b7
      updated: 2026-07-23
-->

---
type: feature
app_type: http
languages: [rust]
capabilities: [streaming-response]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/streaming
---

# Feature: Streaming Response (WASI, Rust)

## When to Use

Use this feature when you want to send a response body as a stream of chunks produced over time, rather than buffering the full body in memory before responding. Suitable for: progressive output, server-sent events, long-running computations emitting incremental results, or any scenario where latency-to-first-byte matters.

## Dependencies

Add to `Cargo.toml` in addition to the base skeleton dependencies:

```toml
futures-lite = "1"
```

Full `[dependencies]` section:

```toml
[dependencies]
wstd = "0.6"
anyhow = "1"
futures-lite = "1"
```

`crate-type` must be `["cdylib"]`.

## Key APIs

### `Body::from_stream`

```rust
Body::from_stream(stream: impl Stream<Item = String>) -> Body
```

- Accepts any `futures_lite::Stream` whose items are `String`.
- The runtime polls the stream as the body is transmitted; chunks are sent to the client as they are produced, not buffered.

### `futures_lite::stream::unfold`

```rust
stream::unfold(initial_state: S, async_fn: F) -> impl Stream<Item = T>
```

- Builds a lazy, stateful stream.
- `initial_state`: seed value passed into the first invocation of `async_fn`.
- `async_fn`: async closure `|state| async move { ... }` that returns:
  - `None` — stream is exhausted, no further items.
  - `Some((item, next_state))` — emit `item` and advance state to `next_state`.
- Items are produced on demand; no items are computed until the runtime polls the stream.

### `wstd::time::Timer`

```rust
Timer::after(duration: Duration) -> Timer
// usage:
Timer::after(Duration::from_millis(200)).wait().await;
```

- Creates a timer that resolves after `duration`.
- `.wait().await` suspends the current async task until the timer fires.
- Use inside the `unfold` closure to introduce delays between chunks.

### `wstd::time::Duration`

```rust
Duration::from_millis(millis: u64) -> Duration
```

- Standard duration constructor; used to specify inter-chunk delay.

## Complete Implementation Pattern

```rust
use futures_lite::stream;
use wstd::http::body::Body;
use wstd::http::{Request, Response};
use wstd::time::{Duration, Timer};

#[wstd::http_server]
async fn main(_request: Request<Body>) -> anyhow::Result<Response<Body>> {
    let chunk_stream = stream::unfold(0u32, |i| async move {
        if i >= 5 {
            return None;
        }
        Timer::after(Duration::from_millis(200)).wait().await;
        Some((format!("chunk {i}\n"), i + 1))
    });

    Ok(Response::builder()
        .status(200)
        .header("content-type", "text/plain; charset=utf-8")
        .body(Body::from_stream(chunk_stream))?)
}
```

## Unfold Pattern Details

| Element | Value in Example | Role |
|---|---|---|
| Initial state | `0u32` | Chunk counter seed |
| Termination condition | `i >= 5` | Stops after 5 chunks |
| Delay | `Duration::from_millis(200)` | 200ms pause before each chunk |
| Emitted item | `format!("chunk {i}\n")` | String payload sent to client |
| Next state | `i + 1` | Increments counter |

## Response Construction

- Status: `200`
- `content-type` header: `text/plain; charset=utf-8`
- Body: `Body::from_stream(chunk_stream)` — stream-backed, not buffered

## Constraints and Notes

- Stream items must be `String` (owned). The stream closure must return `Option<(String, NextState)>`.
- `futures-lite` is not included in the base HTTP skeleton; it must be added explicitly to `Cargo.toml`.
- The runtime polls the stream during transmission. Delays inside the closure (`Timer::after(...).wait().await`) produce real-time pacing visible to the HTTP client.
- To observe streaming behavior: `curl -N https://<app-url>/` (`-N` disables client-side buffering).
- The handler signature ignores the incoming request (`_request`); add request inspection as needed.
- Return type is `anyhow::Result<Response<Body>>`; the `?` operator propagates `Response::builder()` errors.

## See Also

- http-base skeleton (base HTTP handler structure, Cargo.toml baseline)
- FastEdge-sdk-rust HTTP examples (other HTTP feature blueprints)
- wstd crate documentation (Runtime, Body, Timer APIs)
- futures-lite crate documentation (stream combinators, unfold)

## Source Material

### FILE: examples/http/wasi/streaming/src/lib.rs

```rust
/*
 * Copyright 2025 G-Core Innovations SARL
 */
/*
Streaming response example.

Generates a response body on the fly — five text chunks, one every 200ms —
using `Body::from_stream` backed by a `futures_lite::Stream`. The runtime
polls the stream as the body is sent, so chunks flow to the client as they
are produced instead of all at once at the end.

Watch it stream with `curl -N https://<app-url>/` (`-N` disables client-side
buffering).

Mirror of the FastEdge-sdk-js `streaming` example.
*/

use futures_lite::stream;
use wstd::http::body::Body;
use wstd::http::{Request, Response};
use wstd::time::{Duration, Timer};

#[wstd::http_server]
async fn main(_request: Request<Body>) -> anyhow::Result<Response<Body>> {
    let chunk_stream = stream::unfold(0u32, |i| async move {
        if i >= 5 {
            return None;
        }
        Timer::after(Duration::from_millis(200)).wait().await;
        Some((format!("chunk {i}\n"), i + 1))
    });

    Ok(Response::builder()
        .status(200)
        .header("content-type", "text/plain; charset=utf-8")
        .body(Body::from_stream(chunk_stream))?)
}
```


### FILE: examples/http/wasi/streaming/Cargo.toml

```toml
[workspace]

[package]
name = "streaming_wasi"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
wstd = "0.6"
anyhow = "1"
futures-lite = "1"
```
