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
capabilities: [ab-testing, cookies, outbound-http]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/ab_testing
---

# Feature: A/B Testing (WASI, Rust)

Cookie-based A/B testing feature for FastEdge HTTP apps. Reads or creates an `x-fastedge-abid` cookie, deterministically assigns the visitor to weighted variants for each configured test, and proxies the request to a downstream origin with `ab-test-<name>` headers attached. The origin response is returned verbatim with a `set-cookie` header ensuring variant persistence across visits.

## When to Use

Use this feature when you need to split traffic between named variants using a cookie-persisted A/B identifier and forward variant assignments to an upstream origin as request headers.

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `OUTBOUND_URL` | Yes | Downstream origin URL to proxy requests to. Must be non-empty. |

If `OUTBOUND_URL` is missing or empty, the handler returns HTTP 500 with a descriptive message body.

## Cargo.toml

```toml
[workspace]

[package]
name = "ab_testing_wasi"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
wstd = "0.6"
anyhow = "1"
```

No extra dependencies beyond `wstd` and `anyhow`. The base skeleton already supplies both.

## Data Structures

### Variant and Test Declaration

```rust
struct VariantWeight {
    variant: &'static str,
    weight: f64,
}

struct AbTest {
    name: &'static str,
    variants: &'static [VariantWeight],
}
```

Variants are declared at compile time as a static slice. Weights are relative (not required to sum to 100); the assignment logic normalises them.

### Static Test Configuration

```rust
static TESTS: &[AbTest] = &[
    AbTest {
        name: "logo",
        variants: &[
            VariantWeight { variant: "hops", weight: 50.0 },
            VariantWeight { variant: "bottle", weight: 50.0 },
        ],
    },
    AbTest {
        name: "font",
        variants: &[
            VariantWeight { variant: "exo2", weight: 40.0 },
            VariantWeight { variant: "gloria", weight: 65.0 },
            VariantWeight { variant: "standard", weight: 45.0 },
        ],
    },
];
```

Add or modify entries in `TESTS` to configure additional experiments. Each `AbTest` produces one `ab-test-<name>` request header forwarded to the origin.

## Cookie: `x-fastedge-abid`

| Property | Value |
|---|---|
| Cookie name | `x-fastedge-abid` |
| Value format | `"0.NNNN"` — a `f64` in the range `[0.0, 1.0)` |
| Attributes | `Max-Age=31536000; Path=/; Secure; HttpOnly; SameSite=Lax` |

The XID value is used as a stable, visitor-scoped random seed. A returning visitor with a valid cookie receives the same variant assignments on every request.

## Key Functions

### `extract_abid(cookie_header: &str) -> Option<&str>`

Parses the raw `cookie` header string and returns the value of `x-fastedge-abid` if present.

- Splits on `;`, trims whitespace, and searches for the `x-fastedge-abid=` prefix.
- Returns `None` if the cookie is absent.

### `strip_abid(cookie_header: &str) -> String`

Returns the cookie header string with the `x-fastedge-abid` cookie removed.

- Used to ensure the A/B cookie is not forwarded to the upstream origin.
- Filters out empty segments and re-joins with `"; "`.

### `is_valid_xid(xid: &str) -> bool`

Returns `true` if `xid` parses as an `f64` in the range `[0.0, 1.0)`.

### `generate_xid() -> String`

Generates a pseudo-random XID in the form `"0.NNNN"` using request-time nanoseconds (`subsec_nanos % 10000`) as entropy.

**Note:** This is a weak entropy source suitable for development and low-stakes testing. For production, use a cryptographic RNG backed by `wasi-random`.

### `assign_variant<'a>(xid: &str, test: &'a AbTest) -> Option<&'static str>`

Deterministically assigns a variant based on the XID value and the test's weight configuration.

- Parses `xid` as `f64`, multiplies by 100 to get a percentage in `[0.0, 100.0)`.
- Normalises variant weights relative to the total weight sum.
- Iterates over variants, accumulating bucket boundaries; returns the variant whose bucket contains the XID percentage.
- Returns `None` if XID cannot be parsed or if total weight is `0.0`.

## Request Handling Flow

```
Incoming request
  │
  ├─ Read `cookie` header
  │    ├─ `x-fastedge-abid` present and valid → use existing XID
  │    └─ absent or invalid → generate new XID
  │
  ├─ Build outbound request to OUTBOUND_URL
  │    ├─ Copy all headers except `host` and `cookie`
  │    ├─ Re-attach cookie header with abid stripped (if non-empty)
  │    └─ For each test in TESTS: assign variant, attach `ab-test-<name>` header
  │
  ├─ Send outbound request via `Client::new().send()`
  │
  └─ Return origin response
       ├─ Status from origin
       ├─ `content-type` from origin (default: `application/octet-stream`)
       └─ `set-cookie: x-fastedge-abid=<xid>; Max-Age=31536000; Path=/; Secure; HttpOnly; SameSite=Lax`
```

## Outbound HTTP API

```rust
use wstd::http::{Client, Request, Response};
use wstd::http::body::Body;

// Build request
let mut builder = Request::get(&outbound_url);
builder = builder.header("header-name", "value");
let req = builder.body(Body::empty())?;

// Send request
let resp = Client::new().send(req).await?;

// Decompose response
let (parts, mut body) = resp.into_parts();
let body_bytes = body.contents().await?;
let status = parts.status;
let content_type = parts.headers.get("content-type")...;
```

## Response Builder

```rust
Response::builder()
    .status(parts.status)
    .header("content-type", content_type)
    .header("set-cookie", xid_cookie)
    .body(Body::from(body_bytes))?
```

## Error Conditions

| Condition | Behaviour |
|---|---|
| `OUTBOUND_URL` not set or empty | Returns HTTP 500 with message `"OUTBOUND_URL environment variable is not configured"` |
| Outbound request build fails | Returns `Err` (anyhow), message: `"failed to build outbound request: {e}"` |
| Outbound request send fails | Returns `Err` (anyhow), message: `"outbound request failed: {e}"` |
| `assign_variant` receives unparseable XID | Returns `None`; no `ab-test-<name>` header is attached for that test |
| Total variant weight is `0.0` | `assign_variant` returns `None` |

## Header Forwarding Rules

| Header | Action |
|---|---|
| `host` | Dropped — not forwarded to origin |
| `cookie` | Replaced with abid-stripped version; omitted entirely if result is blank |
| `ab-test-<name>` | Added for each test in `TESTS` with the assigned variant value |
| All other headers | Forwarded verbatim if value converts to a valid string |

## See Also

- http-base (base skeleton for HTTP apps)
- fastedge-sdk-rust platform overview
- host-services-rust reference (outbound HTTP, environment variables)
- best-practices reference (cookie security, entropy sources)
