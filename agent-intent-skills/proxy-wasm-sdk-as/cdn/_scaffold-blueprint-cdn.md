# CDN Scaffold Blueprint Instructions

> For shared output format, cross-referencing rules, and exclusions see [_scaffold-blueprint-base.md](../_scaffold-blueprint-base.md)

This file adds CDN-specific structure for scaffold blueprint intent skills in the `cdn/` directory.

### Required sections (in this order)

1. **When to Use** — 1-2 sentences describing when this blueprint should be selected. The agent uses this for matching against user intent.
2. **Dependencies to Add** — npm dependency entries to merge into the base skeleton's package.json. Only list what is NEW beyond the base.
3. **Files to Create** — complete content of any new files this feature adds.
4. **Files to Modify** — for each existing base skeleton file that needs changes:
   - `import` statements to add
   - Code to insert into the handler, with comments indicating placement
   - Which proxy-wasm lifecycle hook(s) the feature code goes into (`onRequestHeaders`, `onRequestBody`, `onResponseHeaders`, `onResponseBody`)
5. **Build Notes** — any special build steps, feature flags, or caveats

### Header removal pitfall — do not attribute to nginx

Calling `remove` on a header on the FastEdge CDN platform **sets the header value to an empty string** rather than truly removing it. This is a **FastEdge platform limitation**, not generic nginx or Envoy behavior. Do not attribute it to "nginx" or any underlying infrastructure.

When documenting header removal, always:
1. State the behavior definitively ("sets to empty string"), not with hedging ("may set to empty string")
2. Attribute to "FastEdge CDN platform", not "nginx"
3. Include the recommended workaround: when checking for header absence, test for both a missing value and an empty string
