# Synthesis Instructions: examples-auth-js.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-auth-js.md`

## Source note
The source `docs/AUTH_PATTERNS.md` is hand-authored in the SDK repo (not produced by `generate-docs.sh`). It is already polished — preserve content faithfully. Apply formatting/cross-referencing rules from the base instructions but do not restructure or invent new patterns.

## Example-specific extraction hints
- API focus: `getSecret(name): string | null` from `fastedge::secret`; `crypto.subtle.importKey`, `crypto.subtle.verify` for HMAC. Preserve `string | null` exactly.
- Bearer token pattern: regex extraction `/^Bearer\s+(.+)$/iu`, comparison against shared secret, 401/403/500 response shape.
- Hono middleware variant: identical logic wrapped as `app.use("/api/*", async (c, next) => { ... await next(); })`.
- HMAC-SHA256 JWT pattern: from `examples/crypto-hmac-jwt/`. Show `base64urlToBytes` helper, `crypto.subtle.importKey` with `{ name: "HMAC", hash: "SHA-256" }`, `verify` against `${header}.${payload}`, exp claim check.
- Crypto capability table: keep the supported-operations table (digest / sign / verify / importKey) — agents need this to know what's available before they suggest libraries.
- Operational notes: never log secrets, request-time only (not module-init), null check before use, rotate via API not redeploy.
- Gotchas focus: secrets returning null when not provisioned, `getSecret` not callable at module scope, `crypto.subtle.encrypt/decrypt/generateKey/deriveKey/exportKey` are NOT available — direct readers to the runtime constraints reference for the full crypto matrix.
