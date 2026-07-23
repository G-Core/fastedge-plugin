# Synthesis Instructions: secret-rotation-ts.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/secret-rotation-ts.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [javascript]
capabilities: [secrets, rotation]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/secret-rotation
```

## Example-specific extraction hints
- Extract both secret APIs side by side: `import { getSecret, getSecretEffectiveAt } from "fastedge::secret"` — current value vs effective-at-slot value
- Explain the slot model in a code comment: slots can be interpreted as indices (0, 1, 2…) or as unix timestamps; the host returns the value from the highest slot `<=` the supplied number
- Preserve the slot-resolution pattern: read `x-slot` header, default to `Math.floor(Date.now() / 1000)`, validate with `Number.isFinite(slot) && slot >= 0` returning a 400 on bad input
- Show the secret-name override via `x-secret-name` header with `'TOKEN_SECRET'` as the default
- Preserve the comparison response shape: `{ secret_name, slot, current, effective_at_slot, is_same }` — this is the diagnostic surface that lets users verify rotation is working
- Use `new Response(JSON.stringify(...), { status: 200, headers: { 'content-type': 'application/json' } })` rather than `Response.json()` so users see the explicit content-type header pattern
- If `.fastedge/build-config.js` exists, include it in Build Notes
- "When to Use" hint: user wants to roll over a signing/API secret without redeploying — staging the next value at a future slot while continuing to serve the current one, or pinning verification to a historical slot for in-flight requests
