---
name: fastedge-docs
disable-model-invocation: false
description: FastEdge documentation, SDK reference, and platform guidance — auto-invoked when users ask about FastEdge
---

# FastEdge Documentation & Reference

You are a FastEdge expert assistant. When the user asks about FastEdge concepts, SDK usage, platform capabilities, error debugging, or best practices, provide accurate answers using the knowledge below and the reference files in `./reference/`.

## Quick Reference

### Supported Languages

- **JavaScript/TypeScript** — via `@gcoredev/fastedge-sdk-js`, built with `fastedge-build ./src/index.js ./<name>.wasm`
- **Rust** — via `fastedge` crate, built with `cargo build --release --target wasm32-wasip1`

### Key SDK Imports (JS)

```typescript
import { getEnv } from "fastedge::env"; // Environment variables
import { getSecret } from "fastedge::secret"; // Encrypted secrets
import { KvStore } from "fastedge::kv"; // Key-value store (globally replicated, read-only)
import { Cache } from "fastedge::cache"; // POP-local cache with TTL + atomic counters
```

### Hono on FastEdge (JS)

```typescript
import { Hono } from "hono";
const app = new Hono();
app.get("/", (c) => c.text("Hello FastEdge!"));

// Wire Hono into FastEdge's Service Worker — do NOT use app.fire()
addEventListener("fetch", (event: FetchEvent) => {
  event.respondWith(app.fetch(event.request));
});
```

For routing, middleware, error handling, and sub-router patterns, read the Hono patterns reference (in the JS HTTP examples).

### Rust Handler

```rust
#[fastedge::http]
fn main(req: Request<Vec<u8>>) -> Result<Response<Vec<u8>>, Error> { ... }
```

### Error Codes

- **530** — App initialization failed (check env vars, binary validity)
- **531** — Runtime error (unhandled exception)
- **532** — Timeout exceeded (optimize hot paths, reduce I/O)
- **533** — Memory limit exceeded (reduce allocations, check for leaks)

### API Base URL

`https://api.gcore.com/fastedge/v1`

Auth header: `Authorization: APIKey $GCORE_API_KEY`

## Reference Files

The reference directory is organised in two layers:
- **`reference/platform/`** — hand-curated platform / agent-behaviour docs (this is the only hand-edited area)
- **All other files in `reference/`** — pipeline-generated from source repos (`auto-updated: true` frontmatter), do not hand-edit

### Platform & agent guidance (`reference/platform/`)

- `./reference/platform/overview.md` — Architecture, PoPs, app types, request lifecycle, resource limits
- `./reference/platform/error-codes.md` — 530–533 debugging strategies
- `./reference/platform/cdn-integration.md` — How CDN apps attach to CDN resources via `options.fastedge`, lifecycle hook configuration, ruleset-based path overrides (replace-not-merge), public-route disable pattern
- `./reference/platform/operations.md` — Operational knobs with time-bounded behaviour (the 30-min `debug` logging toggle)
- `./reference/platform/best-practices.md` — Agent-quality guidance: confirmation discipline, scaffold-first, TDD loop, resource preconditions, observation vs. request, ask-don't-guess
- `./reference/platform/as-constraints.md` — **MANDATORY before writing or reviewing any AssemblyScript CDN app code.** Hard compile-time and runtime constraints where AssemblyScript diverges from TypeScript. Violating these produces wasm that traps at runtime or silently returns wrong values — not a compiler error.

### SDK references (pipeline-generated)

- `./reference/sdk-reference-js.md` — JavaScript SDK API documentation
- `./reference/sdk-reference-rust.md` — Rust SDK core API documentation
- `./reference/sdk-reference-as.md` — AssemblyScript SDK reference (proxy-wasm + FastEdge host APIs). **When using this file, always read `platform/as-constraints.md` first.**
- `./reference/host-services-rust.md` — Rust host services (KV, secrets, dictionary)
- `./reference/cdn-apps-rust.md` — Rust CDN apps (proxy-wasm lifecycle, host services, request/response manipulation)
- `./reference/js-runtime.md` — StarlingMonkey runtime constraints, Node.js incompatibility, SAML implementation guide
- `./reference/quickstart.md` — Getting started

### Language- and app-type-scoped examples (pipeline-generated)

- `./reference/http/` — HTTP-app patterns extracted from `FastEdge-sdk-js/examples/` (fetch, headers, kv-store, cache, geo-redirect, ab-testing, plus Hono routing/middleware, auth-bearer/JWT, proxy-with-transform)
- `./reference/cdn/` — CDN-app patterns from `FastEdge-sdk-rust/examples/cdn/` and `proxy-wasm-sdk-as/examples/` (jwt, geoblock, headers, body, env-secrets, kv-store, properties, ab-testing, etc.)

## Common Questions

**Q: How do I set environment variables for my app?**
Use the API: `PUT /apps/{id}` with `"env_vars": {"KEY": "value"}` in the body. Or set them in the Gcore portal.

**Q: How do I use the KV store?**

```typescript
import { KvStore } from "fastedge::kv";

// Open via static factory — there is no `new KvStore(...)` constructor
const store = KvStore.open("my-store");

// Synchronous; returns ArrayBuffer | null
const buf = store.get("key");
const text = buf ? new TextDecoder().decode(buf) : null;
```

KV stores are **read-only from app code** (no `set` / `delete` / `list`). Provision the store in the Gcore portal, populate via the management API, then read it from the app.

**Q: How do I cache values in a JS app?**
Use `fastedge::cache` — FastEdge's own POP-local cache, not the Web Cache API (`caches.open()` is not available). `Cache` is strongly consistent within a single POP, supports TTL, and has atomic counter primitives. Good for rate limiting, hit counters, and response memoisation.

```typescript
import { Cache } from "fastedge::cache";

// Read
const entry = await Cache.get("my-key");
const text = entry ? await entry.text() : null;

// Write with TTL
await Cache.set("my-key", "value", { ttl: 60 });

// Atomic get-or-populate (avoids thundering herd)
const entry2 = await Cache.getOrSet("my-key", () => "computed-value", { ttl: 60 });
```

See `./reference/sdk-reference-js.md` (Cache section) and `./reference/http/examples-cache-js.md` for the full API including `incr`/`decr` and `delete`.

**Q: What Web APIs are available?**
fetch(), Request, Response, Headers, URL, URLSearchParams, TextEncoder, TextDecoder, crypto.subtle (partial — see js-runtime reference for the algorithm matrix), streams (ReadableStream, WritableStream, TransformStream), CompressionStream / DecompressionStream, setTimeout, setInterval, console.log. `caches` (Web Cache API) is NOT available — use `fastedge::cache` instead. NOT available: `node:crypto`, `node:fs`, `node:buffer`, `process`, `require`, WebSocket, DOM APIs.

**Q: How do I test locally?**

```bash
fastedge-run http -w ./my-app.wasm --port 8080
curl http://localhost:8080/
```

**Q: What's the maximum binary size?**
No fixed limit. The platform rejects uploads beyond ~50MB. Typical JS apps land near 10MB; bundling static assets pushes higher. Aim to stay under 20MB but it is not a strict threshold.

**Q: How do I handle CORS?**
Use Hono's CORS middleware: `import { cors } from "hono/cors"; app.use("/*", cors());`
