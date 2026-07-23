# Synthesis Instructions: template-invoice-ts.md

> For shared output format, sections, extraction rules, and exclusions see [_scaffold-blueprint-http.md](./_scaffold-blueprint-http.md)

## Target file
`plugins/gcore-fastedge/skills/scaffold/reference/http/template-invoice-ts.md`

## Frontmatter
```yaml
type: feature
app_type: http
languages: [javascript]
capabilities: [templating, html, handlebars]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/template-invoice
```

## Example-specific extraction hints
- Extract the Handlebars rendering flow: `import Handlebars from 'handlebars'` → `Handlebars.compile(rawHtmlTemplate)` → `template({ ...data })` → return as `text/html`
- New dependency to declare in `Dependencies to Add`: `"handlebars": "^4.7.9"` (not provided by the http-base skeleton)
- Preserve the three split source modules — `src/css-styles.js`, `src/html-template.js`, `src/logo.js` — and instruct the generator to extract complete contents of each from the source example so the blueprint compiles end-to-end
- Highlight the data-shape that the template consumes: `{ cssStyles, logoBrand, createdDate, dueDate, invoiceNumber, recipientAddress, paymentMethod, paymentId, items[], totalPrice }` — this is the contract callers need to populate
- Show the `getTotalPrice` helper (`items.reduce(...).toFixed(2)`) as the canonical price-aggregation pattern for invoice-style use cases
- Preserve the `text/html` content-type on the response — Handlebars output is raw HTML, not JSON
- Call out that the compiled template is reusable across requests — the `Handlebars.compile` cost is paid once when the module is wizened (top-level evaluation), not per request
- Note: the template, CSS, and logo modules are pure JS string exports — there is no asset pipeline / `fastedge-assets` step here (contrast with the static-assets blueprint)
- "When to Use" hint: user wants to render server-side HTML at the edge from a structured data object using Handlebars templates — invoices, receipts, transactional pages, or any composable HTML response where the inputs change per request but the layout is static
