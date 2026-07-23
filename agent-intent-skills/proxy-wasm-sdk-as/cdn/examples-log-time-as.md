# Synthesis Instructions: examples-log-time-as.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-cdn.md](./_docs-pattern-cdn.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/cdn/examples-log-time-as.md`

## Example-specific extraction hints
- API focus: `getCurrentTime()` returning `u64` milliseconds, `log(level, message)` for logging
- Show `setLogLevel(LogLevelValues.info)` for controlling log verbosity
- Show timestamp formatting patterns (UTC date from milliseconds)
- Import `getCurrentTime` and `setLogLevel` from `@gcoredev/proxy-wasm-sdk-as/assembly/fastedge`
- Import `log` and `LogLevelValues` from `@gcoredev/proxy-wasm-sdk-as/assembly`
- Gotchas: `getCurrentTime` returns milliseconds (not seconds or nanoseconds), logging uses proxy-wasm host (not console.log)
