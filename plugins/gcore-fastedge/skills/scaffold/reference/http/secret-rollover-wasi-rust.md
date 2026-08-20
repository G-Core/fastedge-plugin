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
capabilities: [secrets, secret-rollover]
base_skeleton: http-base
source_example: FastEdge-sdk-rust/examples/http/wasi/secret_rollover
---

# Secret Rollover (WASI, Rust)

Slot-based secret retrieval for zero-downtime secret rotation. Uses `secret::get_effective_at()` to look up which secret value was active at a given slot, enabling backward-compatible token validation after rotation.

## When to Use

Use this pattern when:
- Rotating secrets (e.g. signing keys, passwords) without invalidating tokens issued before the rotation
- Tokens carry an `iat` (issued-at) timestamp and must be validated against the secret that was active at issuance
- You need to verify that rotation is working before removing the old slot

## Slot Mechanics

Slots use a **greatest-match rule**: the slot with the highest value `<= effective_at` is returned.

```
Secret slots: { 0: "old-password", 1741790697: "new-password" }

get_effective_at("TOKEN_SECRET", 0)          → "old-password"
get_effective_at("TOKEN_SECRET", 100)        → "old-password"
get_effective_at("TOKEN_SECRET", 1741790697) → "new-password"
get_effective_at("TOKEN_SECRET", 9999999999) → "new-password"
```

Slot `0` serves as the baseline — always matched when no higher slot qualifies.

Usage as indices:
```
get_effective_at("token-secret", 0) -> "original_password"
get_effective_at("token-secret", 3) -> "original_password"
get_effective_at("token-secret", 5) -> slot 5's value (if exists)
```

Usage as timestamps: a token's `iat` claim determines which password to validate against. `get_effective_at("token-secret", claims.iat)` returns the password that was effective when the token was issued.

## API Reference

### `secret::get`

```rust
fastedge::secret::get(name: &str) -> Result<Option<String>, ...>
```

Returns the current (latest-slot) value of the named secret.

| Parameter | Type | Description |
|---|---|---|
| `name` | `&str` | Secret name as configured in the FastEdge dashboard |

**Returns**: `Ok(Some(value))` if the secret exists, `Ok(None)` if not found, `Err` on retrieval failure.

---

### `secret::get_effective_at`

```rust
fastedge::secret::get_effective_at(name: &str, slot: u32) -> Result<Option<String>, ...>
```

Returns the secret value whose slot is the highest value `<= slot` (greatest-match rule).

| Parameter | Type | Description |
|---|---|---|
| `name` | `&str` | Secret name as configured in the FastEdge dashboard |
| `slot` | `u32` | Slot index or Unix timestamp (seconds) to query |

**Returns**: `Ok(Some(value))` for the matched slot, `Ok(None)` if no slot matches, `Err` on retrieval failure.

**Slot-as-timestamp pattern**: Pass a JWT `iat` claim (Unix timestamp as `u32`) to retrieve the secret that was active when the token was issued.

## Request Interface

| Header | Default | Description |
|---|---|---|
| `x-secret-name` | `TOKEN_SECRET` | Name of the secret to query |
| `x-slot` | current Unix timestamp (`u32`) | Slot passed to `get_effective_at` |

The `x-slot` header is parsed as `u32`. If absent or unparseable, falls back to `SystemTime::now()` converted to Unix seconds cast to `u32`.

## Response

HTTP 200, `content-type: application/json`.

```json
{
  "secret_name": "TOKEN_SECRET",
  "slot": 0,
  "current": "new-password",
  "effective_at_slot": "old-password",
  "is_same": false
}
```

| Field | Type | Description |
|---|---|---|
| `secret_name` | string | Name of the queried secret |
| `slot` | number | Slot value used for the lookup |
| `current` | string or null | Value from `secret::get` (latest slot) |
| `effective_at_slot` | string or null | Value from `secret::get_effective_at` at `slot` |
| `is_same` | boolean | Whether `current == effective_at_slot` |

## Secret Configuration Format

```json
{
  "secret": {
    "name": "token-secret",
    "secret_slots": [
      { "slot": 0, "value": "original_password" },
      { "slot": 1741790697, "value": "new_password" }
    ]
  }
}
```

## Dependencies (`Cargo.toml`)

```toml
[dependencies]
wstd = "0.6"
fastedge = "0.4"
anyhow = "1"
serde_json = "1"

[lib]
crate-type = ["cdylib"]
```

Required additions beyond the base HTTP skeleton:
- `fastedge = "0.4"` — provides `fastedge::secret` module
- `serde_json = "1"` — JSON response serialization

## Implementation Pattern

```rust
use fastedge::secret;
use std::time::{SystemTime, UNIX_EPOCH};

// Read slot from header, default to current Unix timestamp
let slot: u32 = request
    .headers()
    .get("x-slot")
    .and_then(|v| v.to_str().ok())
    .and_then(|v| v.parse().ok())
    .unwrap_or_else(|| {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("Time went backwards")
            .as_secs() as u32
    });

let secret_name = request
    .headers()
    .get("x-secret-name")
    .and_then(|v| v.to_str().ok())
    .unwrap_or("TOKEN_SECRET");

// Current (latest) value
let current = secret::get(secret_name)
    .map_err(|e| anyhow!("secret::get failed: {e}"))?;

// Value effective at the given slot
let effective = secret::get_effective_at(secret_name, slot)
    .map_err(|e| anyhow!("secret::get_effective_at failed: {e}"))?;

let result = json!({
    "secret_name": secret_name,
    "slot": slot,
    "current": current,
    "effective_at_slot": effective,
    "is_same": current == effective,
});
```

## Full Source

```rust
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::anyhow;
use fastedge::secret;
use serde_json::json;
use wstd::http::body::Body;
use wstd::http::{Request, Response};

#[wstd::http_server]
async fn main(request: Request<Body>) -> anyhow::Result<Response<Body>> {
    let slot: u32 = request
        .headers()
        .get("x-slot")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.parse().ok())
        .unwrap_or_else(|| {
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("Time went backwards")
                .as_secs() as u32
        });

    let secret_name = request
        .headers()
        .get("x-secret-name")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("TOKEN_SECRET");

    let current = secret::get(secret_name).map_err(|e| anyhow!("secret::get failed: {e}"))?;

    let effective = secret::get_effective_at(secret_name, slot)
        .map_err(|e| anyhow!("secret::get_effective_at failed: {e}"))?;

    let result = json!({
        "secret_name": secret_name,
        "slot": slot,
        "current": current,
        "effective_at_slot": effective,
        "is_same": current == effective,
    });

    Ok(Response::builder()
        .status(200)
        .header("content-type", "application/json")
        .body(Body::from(result.to_string()))?)
}
```

## Build

```sh
cargo build --release
# Output: target/wasm32-wasip2/release/secret_rollover.wasm
```

## See Also

- fastedge::secret module reference (Rust SDK reference)
- http-base skeleton (base HTTP app structure)
- platform-overview (secret management configuration)
- best-practices (secret rotation strategies)
