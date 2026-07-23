# Synthesis Instructions: bloom-filter-denylist-ts.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/bloom-filter-denylist-ts.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [javascript]
capabilities: [kv-store, denylist, bloom-filter]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/bloom-filter-denylist
```

## Example-specific extraction hints
- Extract the bloom-filter membership pattern: `import { KvStore } from "fastedge::kv"` plus `store.bfExists(BLOOM_KEY, candidate)` — returns a synchronous boolean
- Show the env-driven store name: `import { getEnv } from "fastedge::env"`, `getEnv('DENYLIST_STORE')`, with a 500 if it is not configured
- Preserve the `event.client.address` lookup for the candidate IP, including the 500 fallback when the address is unavailable
- Call out the bloom-filter false-positive trade-off in a code comment: "maybe in set" — acceptable for over-blocking (denylists), unacceptable for exact-membership use cases (allowlists) — use `KvStore.get()` for the latter
- Preserve the `'blocked-ips'` constant as the bloom-filter key under which the IP set is stored (so users see where they upload the bloom payload)
- Wrap the `bfExists` call in its own try/catch returning a 500 JSON envelope, separate from the env-missing branch
- If `.fastedge/build-config.js` exists, include it in Build Notes
- "When to Use" hint: user wants a low-memory, near-constant-time membership check at the edge (IP denylist, leaked-password check, abuse-token blocking) where occasional false positives are acceptable
