# Synthesis Instructions: large-dictionary-as.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-cdn.md](./_scaffold-blueprint-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/cdn/large-dictionary-as.md`

## Frontmatter
```yaml
type: feature
app_type: cdn
languages: [assemblyscript]
capabilities: [dictionary, large-config]
base_skeleton: cdn-base
source_example: proxy-wasm-sdk-as/examples/largeDictionary
```

## Example-specific extraction hints
- Extract `getDictionary(name)` from `@gcoredev/proxy-wasm-sdk-as/assembly/fastedge` — returns `string`; use this for env values that may exceed the 64KB WASI environment-variable limit
- Contrast with `getEnv`: for normal-sized values (< 64KB) prefer `getEnv` for lower overhead; reach for `getDictionary` only when payload size demands it
- Show minimal usage: read in `onRequestHeaders`, forward size or summary via a request header (`stream_context.headers.request.add("x-config-size", size.toString())`)
- Show empty-string check (`config.length === 0`) for missing values — never null
- No new dependencies beyond the base skeleton; all logic in `onRequestHeaders`
- "When to Use" hint: user needs to read configuration env values that exceed the 64KB WASI limit at the CDN layer
