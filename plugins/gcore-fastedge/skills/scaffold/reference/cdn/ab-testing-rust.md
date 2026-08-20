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
app_type: cdn
languages: [rust]
capabilities: [ab-testing, cookies, traffic-splitting]
base_skeleton: cdn-base
source_example: FastEdge-sdk-rust/examples/cdn/ab_testing
---

# Feature: A/B Testing (CDN Rust)

## When to Use

Use this blueprint when the user wants to split CDN traffic between A/B variants using cookies and path rewriting at the CDN layer. This is a proxy-wasm filter that assigns users to variant A or B via a persistent cookie, then rewrites the request path to route to different origin path prefixes. The assignment is sticky across sessions via a `Set-Cookie` response header. No origin-side changes are required — all routing logic lives in the Wasm filter.

## Dependencies to Add

No extra dependencies beyond the base `cdn-base` skeleton. Only `proxy-wasm = "0.2"` is required.

Source `Cargo.toml` for reference:
```toml
[workspace]

[package]
name = "ab_testing"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
proxy-wasm = "0.2"
```

## Files to Create

No extra files beyond the main source file. The A/B testing example is self-contained in a single source file.

## Files to Modify

### lib.rs (or ab_testing.rs)

The example uses `[lib]` with `crate-type = ["cdylib"]`. In the base skeleton, replace the main source file content with the following implementation.

**Replace with:**
```rust
use proxy_wasm::traits::*;
use proxy_wasm::types::*;
use std::env;
use std::time::UNIX_EPOCH;

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Info);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(AbTestingRoot) });
}}

struct AbTestingRoot;

impl Context for AbTestingRoot {}

impl RootContext for AbTestingRoot {
    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }

    fn create_http_context(&self, _: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(AbTestingContext))
    }
}

struct AbTestingContext;

impl Context for AbTestingContext {}

impl HttpContext for AbTestingContext {
    fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
        let Ok(experiment_name) = env::var("EXPERIMENT_NAME") else {
            self.send_http_response(
                500,
                vec![],
                Some(b"App misconfigured - EXPERIMENT_NAME must be set"),
            );
            return Action::Pause;
        };

        let Ok(variant_a_path) = env::var("VARIANT_A_PATH") else {
            self.send_http_response(
                500,
                vec![],
                Some(b"App misconfigured - VARIANT_A_PATH must be set"),
            );
            return Action::Pause;
        };

        let Ok(variant_b_path) = env::var("VARIANT_B_PATH") else {
            self.send_http_response(
                500,
                vec![],
                Some(b"App misconfigured - VARIANT_B_PATH must be set"),
            );
            return Action::Pause;
        };

        let cookie_name = format!("fe_exp_{}", experiment_name);

        // Check for existing experiment cookie
        let cookie_header = self
            .get_http_request_header("Cookie")
            .unwrap_or_default();
        let mut assigned = get_cookie_value(&cookie_header, &cookie_name);

        // Assign variant if not already set
        if assigned != "A" && assigned != "B" {
            let now = self
                .get_current_time()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis();
            assigned = if now % 2 == 0 { "A" } else { "B" }.to_string();
        }

        // Rewrite request path
        let path = self
            .get_property(vec!["request.path"])
            .and_then(|bytes| String::from_utf8(bytes).ok())
            .unwrap_or_else(|| "/".to_string());

        let variant_path = if assigned == "A" {
            &variant_a_path
        } else {
            &variant_b_path
        };
        let new_path = format!("{}{}", variant_path, path);

        // Update the request path directly to avoid ambiguous URL rewriting.
        self.set_property(vec!["request.path"], Some(new_path.as_bytes()));

        // Add variant headers for upstream visibility
        self.add_http_request_header("X-Experiment", &experiment_name);
        self.add_http_request_header("X-Variant", &assigned);

        println!(
            "A/B test \"{}\": variant {}, path {}",
            experiment_name, assigned, new_path
        );

        Action::Continue
    }

    fn on_http_response_headers(&mut self, _: usize, _: bool) -> Action {
        // Recover the assigned variant and experiment name from the request headers set in
        // on_http_request_headers. Instance state does not survive the nginx -> core-proxy hop.
        let Some(variant) = self.get_http_request_header("X-Variant") else {
            return Action::Continue;
        };
        let Some(experiment_name) = self.get_http_request_header("X-Experiment") else {
            return Action::Continue;
        };

        let cookie = format!(
            "fe_exp_{}={}; Path=/; Max-Age=86400; SameSite=Lax",
            experiment_name, variant
        );
        self.add_http_response_header("Set-Cookie", &cookie);
        self.add_http_response_header("X-Variant", &variant);

        Action::Continue
    }
}

fn get_cookie_value(cookie_header: &str, name: &str) -> String {
    if cookie_header.is_empty() {
        return String::new();
    }
    let prefix = format!("{}=", name);
    for pair in cookie_header.split(';') {
        let pair = pair.trim();
        if let Some(value) = pair.strip_prefix(&prefix) {
            return value.to_string();
        }
    }
    String::new()
}
```

### Cargo.toml

No additional dependencies beyond the base skeleton. Ensure `crate-type = ["cdylib"]` is set under `[lib]`.

## A/B Assignment and Routing Flow

The filter implements two hooks: `on_http_request_headers` (variant assignment + path rewrite) and `on_http_response_headers` (cookie persistence). State is shared between hooks via request headers set on the outbound request (`X-Variant`, `X-Experiment`) and read back in the response hook. `AbTestingContext` is a unit struct with no fields — instance state does not survive the nginx → core-proxy hop.

### Request phase (`on_http_request_headers`)

Executed in order:

1. **Env var validation** — Reads `EXPERIMENT_NAME`, `VARIANT_A_PATH`, `VARIANT_B_PATH`. Returns `500` with a descriptive message body if any is missing. Errors are checked sequentially — if `EXPERIMENT_NAME` is missing, the remaining vars are not checked.
2. **Cookie lookup** — Constructs cookie name `fe_exp_<EXPERIMENT_NAME>`. Reads `Cookie` request header; calls `get_cookie_value` to extract any existing assignment (`"A"` or `"B"`).
3. **Variant assignment** — If the cookie value is not exactly `"A"` or `"B"`, assigns a new variant using `self.get_current_time().duration_since(UNIX_EPOCH).as_millis() % 2`: `0` → `"A"`, `1` → `"B"`.
4. **Path rewrite** — Reads `request.path` property via `self.get_property(vec!["request.path"])`. Prepends the variant-specific path prefix (`VARIANT_A_PATH` or `VARIANT_B_PATH`). Writes back with `self.set_property(vec!["request.path"], Some(new_path.as_bytes()))`. Falls back to `"/"` if the property is absent or not valid UTF-8.
5. **Upstream headers** — Adds `X-Experiment: <experiment_name>` and `X-Variant: <assigned>` to the request for origin visibility. These headers also serve as the cross-hook state carrier for the response phase.
6. **Logging** — Calls `println!("A/B test \"{}\": variant {}, path {}", ...)` with experiment name, variant, and rewritten path.
7. **Returns** `Action::Continue`.

### Response phase (`on_http_response_headers`)

1. **State recovery** — Reads `X-Variant` and `X-Experiment` from the request headers (set during the request phase). Returns `Action::Continue` immediately if either is absent.
2. **Set-Cookie** — Adds `Set-Cookie: fe_exp_<experiment_name>=<variant>; Path=/; Max-Age=86400; SameSite=Lax` to persist the assignment for 24 hours.
3. **X-Variant header** — Adds `X-Variant: <variant>` to the response for client/debug visibility.
4. **Returns** `Action::Continue`.

## Cookie Parsing Helper

```rust
fn get_cookie_value(cookie_header: &str, name: &str) -> String
```

- **Parameters:** `cookie_header` — raw value of the `Cookie` request header; `name` — exact cookie name to look up.
- **Returns:** The cookie value string if found; empty `String` if not found or if `cookie_header` is empty.
- **Logic:** Splits `cookie_header` on `';'`, trims whitespace from each pair, checks for prefix `"<name>="` using `strip_prefix`. Returns the first match.
- **No URL-decoding** is applied — values are returned as-is from the header.

## Cross-Hook State

`AbTestingContext` is a unit struct (`struct AbTestingContext;`) with no fields. Instance state does not persist across the nginx → core-proxy hop between request and response phases. The response hook recovers state by reading from the request headers that were written during the request phase:

| Header | Written in | Read in | Purpose |
|--------|-----------|---------|---------|
| `X-Variant` | `on_http_request_headers` | `on_http_response_headers` | Variant assignment (`"A"` or `"B"`); absence signals no assignment was made |
| `X-Experiment` | `on_http_request_headers` | `on_http_response_headers` | Used to construct the `Set-Cookie` name |

Both headers are also forwarded to origin for upstream visibility.

## Required Environment Variables

Configure these in the FastEdge dashboard under the app's environment variables:

| Variable | Required | Description |
|----------|----------|-------------|
| `EXPERIMENT_NAME` | Yes | Identifier for the experiment. Used to construct the cookie name `fe_exp_<EXPERIMENT_NAME>`. |
| `VARIANT_A_PATH` | Yes | Path prefix prepended to the original request path for variant A users (e.g. `/a`). |
| `VARIANT_B_PATH` | Yes | Path prefix prepended to the original request path for variant B users (e.g. `/b`). |

## Error Conditions

| Condition | Response Code | Body |
|-----------|---------------|------|
| `EXPERIMENT_NAME` env var missing | 500 | `App misconfigured - EXPERIMENT_NAME must be set` |
| `VARIANT_A_PATH` env var missing | 500 | `App misconfigured - VARIANT_A_PATH must be set` |
| `VARIANT_B_PATH` env var missing | 500 | `App misconfigured - VARIANT_B_PATH must be set` |
| All env vars present; cookie absent or invalid | — | Variant assigned via time-based randomization; `Action::Continue` |
| All env vars present; valid cookie found | — | Existing variant respected; `Action::Continue` |

Note: errors are checked sequentially — if `EXPERIMENT_NAME` is missing, `VARIANT_A_PATH` and `VARIANT_B_PATH` are not checked.

## Key Patterns

- **`proxy_wasm::main!`** macro — CDN app entry point. Sets log level and registers the root context. Not `#[fastedge::http]`.
- **`RootContext` + `HttpContext` trait pair** — `RootContext` creates per-request `AbTestingContext` instances via `create_http_context`. Both must implement `Context`.
- **`AbTestingContext` is a unit struct** — no fields. State is not stored on the instance; it is recovered from request headers in the response phase.
- **`get_type()`** — must return `Some(ContextType::HttpContext)` on `RootContext`.
- **`on_http_request_headers(&mut self, _: usize, _: bool) -> Action`** — request headers phase hook. Returns `Action::Continue` to allow; calls `send_http_response` then returns `Action::Pause` to short-circuit.
- **`on_http_response_headers(&mut self, _: usize, _: bool) -> Action`** — response headers phase hook. Used here to recover state from request headers and set the sticky cookie and response header.
- **`self.get_http_request_header(name: &str) -> Option<String>`** — reads a single request header by name. Used in the response hook to recover `X-Variant` and `X-Experiment`.
- **`self.get_property(vec!["request.path"]) -> Option<Vec<u8>>`** — reads the current request path as raw bytes from the FastEdge platform property bag.
- **`self.set_property(vec!["request.path"], Some(&[u8]))`** — writes back the rewritten path. This modifies the request before it is forwarded to origin.
- **`self.add_http_request_header(name, value)`** — appends a header to the outbound request (sent to origin). Also used as the cross-hook state carrier.
- **`self.add_http_response_header(name, value)`** — appends a header to the outbound response (sent to client).
- **`self.get_current_time()`** — returns `SystemTime`; used instead of `SystemTime::now()` to ensure the proxy-wasm host provides the clock (consistent with the sandboxed execution environment).
- **`println!(...)`** — standard Rust macro for logging output within the FastEdge Wasm environment.
- **`send_http_response(status: u32, headers: Vec<...>, body: Option<&[u8]>)`** — sends a synthetic response. Always paired with `return Action::Pause`.
- **Cookie format:** `fe_exp_<experiment_name>=<variant>; Path=/; Max-Age=86400; SameSite=Lax` — 24-hour session stickiness, site-wide path, Lax same-site policy.

## Build Notes

Standard Rust CDN build:

```bash
cargo build --release --target wasm32-wasip1
```

Requires `.cargo/config.toml`:
```toml
[build]
target = "wasm32-wasip1"
```

Output binary: `target/wasm32-wasip1/release/ab_testing.wasm`

## See Also

- cdn-base skeleton reference (base proxy-wasm project structure for CDN Rust apps)
- FastEdge SDK Rust reference (proxy-wasm trait definitions and types)
- platform-overview reference (request.path property and platform property bag)
- deploy skill reference (uploading and registering the compiled WASM binary)
- headers feature blueprint (patterns for reading and writing request/response headers)
