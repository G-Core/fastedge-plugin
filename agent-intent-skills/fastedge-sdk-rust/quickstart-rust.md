# Synthesis Instructions: quickstart-rust.md

> For shared cross-referencing rules, extraction rules, and accuracy constraints see [_docs-pattern-base.md](./_docs-pattern-base.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/quickstart-rust.md`

## Audience
AI agents onboarding new Rust developers to FastEdge — guiding them from zero to a deployed first app.

## Output goal
A linear, copy-pasteable getting-started guide for Rust HTTP apps. Agents use this to walk users through their first FastEdge Rust app. Every command and code snippet must work as-is against the documented SDK version. CDN apps are referenced briefly but the deep-dive lives in the CDN apps reference.

## Required sections (in this order)

1. **Prerequisites** — Rust toolchain (stable), `wasm32-wasip1` target, `wasm32-wasip2` target. One line each. Include the two `rustup target add` commands.

2. **Create a new project** — `cargo new --lib`, the required `crate-type = ["cdylib"]` line in Cargo.toml. No elaboration on workspace setups.

3. **Async handler (recommended)** — Brief framing: this is the recommended path. `wstd` and `anyhow` deps. Complete `#[wstd::http_server]` example (~10 lines). Build with `--target wasm32-wasip2`. Mention the `.cargo/config.toml` shortcut so `--target` does not need to be passed every build.

4. **Sync handler (alternative)** — Brief framing: simpler, no async. `fastedge` and `anyhow` deps. Complete `#[fastedge::http]` example (~10 lines). Build with `--target wasm32-wasip1`. Note this path is suited to simple synchronous request/response processing; new async apps should prefer the `wstd` handler.

5. **Build summary table** — Two-row table: handler path → build command. Reinforces the wasip1 vs wasip2 split.

6. **CDN apps note** — One short paragraph: CDN apps use a different handler architecture (proxy-wasm) and have access to request properties such as geolocation, client IP, and matched CDN rule metadata. Direct readers to the CDN apps reference using a descriptive topic term per the cross-referencing rules — never a filename.

7. **Next steps** — Bullet list referencing related topics by descriptive name only:
   - SDK API reference — handler macros, Body type, outbound HTTP, errors
   - Host services reference — KV store, secrets, dictionary
   - CDN apps reference — proxy-wasm lifecycle and API surface

## What to exclude
- Full feature flag matrix (mention enabling `json` as the most common case; that's it)
- Outbound HTTP, secrets, KV details (those belong in their own references)
- Cargo workspace patterns
- Troubleshooting / common errors

## Quality bar
Both handler examples must compile against the documented `fastedge` and `wstd` versions. The handler distinction (async/wasip2 vs sync/wasip1) must be unambiguous. Type signatures (`Request<Body>`, `Response<Body>`, `anyhow::Result`) must match the source exactly.
