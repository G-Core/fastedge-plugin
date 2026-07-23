# Synthesis Instructions: examples-hono-js.md

> For shared output format, sections, extraction rules, and exclusions see [_docs-pattern-http.md](./_docs-pattern-http.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/http/examples-hono-js.md`

## Source note
The source `docs/HONO_PATTERNS.md` is hand-authored in the SDK repo (not produced by `generate-docs.sh`). It is already polished — preserve content faithfully. Apply formatting/cross-referencing rules from the base instructions but do not restructure or invent new patterns.

## Example-specific extraction hints
- API focus: `Hono` constructor, `app.get/post/all`, `app.use`, `app.route`, `app.onError`, `app.notFound`, `app.fetch`. Show import paths (`hono`, `hono/cors`, `hono/logger`, `hono/secure-headers`).
- FastEdge integration: must use `event.respondWith(app.fetch(event.request))`. Call out that `app.fire()` conflicts with the FastEdge Service Worker model — this is the most important gotcha.
- Routing: cover basic routes, path params (`c.req.param`), wildcards, sub-routers via `app.route()` with route-ordering caveat (sub-routers before catch-alls).
- Middleware: built-in (cors / logger / secureHeaders), path-scoped (`app.use("/api/*", ...)`), custom `async (c, next) => { ... await next(); }` pattern.
- Error handling: `app.onError` and `app.notFound`. Note that without `onError`, unhandled exceptions surface as FastEdge 531.
- Tree-shaking: prefer path-specific imports (`hono/cors`) over umbrella `hono/middleware`.
- Cross-references: when referencing auth or proxy patterns, use descriptive topic terms per the base cross-referencing rule — never link to `examples/crypto-hmac-jwt/` or `examples/outbound-modify-response/` from this doc, those examples do not use Hono.
