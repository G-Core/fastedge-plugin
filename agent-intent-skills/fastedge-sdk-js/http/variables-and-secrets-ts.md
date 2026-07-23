# Synthesis Instructions: variables-and-secrets-ts.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/variables-and-secrets-ts.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [javascript]
capabilities: [env, secrets]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/variables-and-secrets
```

## Example-specific extraction hints
- Extract the two complementary imports side by side: `import { getEnv } from "fastedge::env"` and `import { getSecret } from "fastedge::secret"`
- Show the `?? ''` fallback pattern on both calls — both APIs return `string | null` and must not be inlined into template strings without a null guard
- Call out the request-time constraint: both `getEnv` and `getSecret` must be called inside the fetch handler, not at module scope (they read per-request configuration)
- Reinforce the trust model in a comment: env vars are visible in the app config; secrets are write-only — operators upload them but cannot read them back through the API
- "When to Use" hint: user wants to parameterise a worker with non-sensitive configuration (`getEnv`) and sensitive credentials (`getSecret`) without baking either into the WASM binary
