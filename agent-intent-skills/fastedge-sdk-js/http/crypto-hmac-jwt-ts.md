# Synthesis Instructions: crypto-hmac-jwt-ts.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/crypto-hmac-jwt-ts.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [javascript]
capabilities: [auth, jwt, crypto]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/crypto-hmac-jwt
```

## Example-specific extraction hints
- Extract the full HS256 JWT verification flow using the WebCrypto-native APIs available in the FastEdge runtime: `crypto.subtle.importKey('raw', …, { name: 'HMAC', hash: 'SHA-256' }, false, ['verify'])` then `crypto.subtle.verify('HMAC', key, signature, signedData)`
- Preserve the helper `base64urlToBytes` (atob + url-safe substitutions + padding) — base64url decode is not built in and the helper is part of the blueprint surface
- Show the three-segment split and the encoded-header / encoded-payload / encoded-signature destructuring
- Preserve the `exp` claim check: `if (typeof claims.exp === 'number' && Math.floor(Date.now() / 1000) >= claims.exp)` throwing `'token expired'`
- Show the secret retrieval pattern: `import { getSecret } from "fastedge::secret"`, `getSecret('JWT_SECRET')`, with a 500 envelope when the secret is not configured
- Preserve the Bearer header parsing: `/^Bearer\s+(.+)$/iu` match against the `authorization` header, with a 401 envelope on missing/malformed
- Distinguish the two error envelopes: 401 for auth failures (missing header, invalid signature, expired claim) vs 500 for misconfigured secret — both return `{ ok: false, error }`
- Note that `TextEncoder`/`TextDecoder` are top-level singletons reused across requests
- If `.fastedge/build-config.js` exists, include it in Build Notes
- "When to Use" hint: user wants to verify HS256 JWTs at the edge using only the runtime's built-in WebCrypto (no third-party JWT library), with the signing secret stored in FastEdge secrets
