# Synthesis Instructions: template-invoice-ab-testing-ts.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/template-invoice-ab-testing-ts.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [javascript]
capabilities: [templating, html, handlebars, ab-testing]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/template-invoice-ab-testing
```

## Example-specific extraction hints
- This blueprint extends the template-invoice pattern with header-driven variant selection — preserve both layers
- New dependency to declare in `Dependencies to Add`: `"handlebars": "^4.7.9"` (not provided by the http-base skeleton)
- Extract the variant inputs from request headers: `request.headers.get('ab-test-logo') === 'bottle'` and `request.headers.get('ab-test-font')` — these drive the asset and style selectors
- Preserve the three split source modules — `src/css-styles.js` (exports `getStyles(font)`), `src/html-template.js` (exports `htmlTemplate(font)`), `src/logo.js` (exports `getLogoBrand(isBottle)`) — and instruct the generator to extract complete contents from the source example. Each module accepts the relevant variant input and returns the variant-specific string
- Show the pipeline order: read variant headers → resolve `logo`, `cssStyles`, `rawHtmlTemplate` from the three helpers → compile with Handlebars → render with the merged data object
- Preserve the data shape passed to the template: `{ cssStyles, logo, ...invoiceData, totalPrice }` — note the renamed `logo` field (vs `logoBrand` in the non-AB blueprint)
- IMPORTANT: the manifest description mentions "cookie-based variant selection" but the actual source uses `ab-test-logo` / `ab-test-font` request headers — preserve the header-based implementation; do not invent cookie handling
- Mention that variant assignment is delegated to the caller (the upstream/load-balancer sets the test headers) — this blueprint renders variants rather than choosing them, so it pairs naturally with an upstream A/B routing layer
- Preserve the `text/html` content-type on the response
- "When to Use" hint: user wants to render HTML templates with per-request A/B variants (alternative logos, fonts, layouts) selected by upstream-assigned headers, while keeping the Handlebars rendering pipeline otherwise unchanged
