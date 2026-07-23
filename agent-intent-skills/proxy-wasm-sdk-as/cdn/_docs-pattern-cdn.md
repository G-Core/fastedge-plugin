# CDN Example Docs Pattern Instructions

> For shared output format, cross-referencing rules, extraction rules, accuracy constraints, and exclusions see [_docs-pattern-base.md](../_docs-pattern-base.md)

This file adds CDN-example-specific structure for docs pattern intent skills in the `cdn/` directory.

### Required sections (in this order)

1. **Overview** — 1-2 sentences: what this capability is and when to use it in FastEdge CDN (proxy-wasm) apps
2. **API Patterns** — key API calls with signatures, import paths, return types, and brief usage notes. Note which proxy-wasm lifecycle hooks are involved.
3. **Common Patterns** — 2-3 short code snippets showing idiomatic AssemblyScript usage of the capability within proxy-wasm hooks
4. **Gotchas** — non-obvious constraints, AssemblyScript-specific limitations (no closures over mutable state, explicit numeric types, no try/catch), WASM-specific limits
5. **Related** — cross-references to other reference topics using descriptive terms (see cross-referencing rules in base)

### Header removal pitfall — do not attribute to nginx

Calling `remove` on a header on the FastEdge CDN platform **sets the header value to an empty string** rather than truly removing it. This is a **FastEdge platform limitation**, not generic nginx or Envoy behavior. Do not attribute it to "nginx" or any underlying infrastructure.

When documenting header removal, always:
1. State the behavior definitively ("sets to empty string"), not with hedging ("may set to empty string")
2. Attribute to "FastEdge CDN platform", not "nginx"
3. Include the recommended workaround: when checking for header absence, test for both a missing value and an empty string
