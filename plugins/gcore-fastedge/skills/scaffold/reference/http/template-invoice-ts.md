<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-js
      ref: main
      commit: b78b2a80317bb632af88010816d3e54afd3bd72d
      updated: 2026-06-16
-->

---
type: feature
app_type: http
languages: [javascript]
capabilities: [templating, html, handlebars]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/template-invoice
---

# Feature Blueprint: Handlebars HTML Templating (template-invoice)

## When to Use

Use this blueprint when the user wants to render server-side HTML at the edge from a structured data object using Handlebars templates — invoices, receipts, transactional pages, or any composable HTML response where the inputs change per request but the layout is static.

## Base Skeleton

Extends: `http-base`

## Dependencies to Add

Add to `package.json` `dependencies` (not provided by http-base skeleton):

```json
"handlebars": "^4.7.9"
```

The `@gcoredev/fastedge-sdk-js` dependency is inherited from the base skeleton and must remain.

## Source Module Structure

The feature requires three split source modules in addition to `src/index.js`. The generator must extract the complete contents of each from the source example so the blueprint compiles end-to-end:

| File | Purpose |
|---|---|
| `src/css-styles.js` | Exports `cssStyles` — a plain JS string containing CSS for the HTML template |
| `src/html-template.js` | Exports `htmlTemplate()` — a function returning the raw Handlebars HTML template string |
| `src/logo.js` | Exports `logoBrand` — a plain JS string containing the logo markup or data URI |

These modules are pure JS string exports. There is no asset pipeline or `fastedge-assets` step — contrast this with the static-assets blueprint.

## Handlebars Rendering Flow

```
import Handlebars from 'handlebars'
       ↓
htmlTemplate()            → raw Handlebars template string
       ↓
Handlebars.compile(...)   → compiled template function (reusable)
       ↓
template({ ...data })     → rendered HTML string
       ↓
new Response(html, { status: 200, headers: { 'content-type': 'text/html' } })
```

## Template Data Contract

The compiled template function accepts the following data shape. Callers must populate all fields:

| Field | Type | Description |
|---|---|---|
| `cssStyles` | `string` | CSS string injected into the template |
| `logoBrand` | `string` | Logo markup or data URI |
| `createdDate` | `string` | Invoice creation date (e.g. `'March 4, 2024'`) |
| `dueDate` | `string` | Payment due date (e.g. `'April 19, 2024'`) |
| `invoiceNumber` | `string` | Invoice identifier |
| `recipientAddress` | `object` | `{ name, address1, address2 }` |
| `recipientAddress.name` | `string` | Recipient full name |
| `recipientAddress.address1` | `string` | Street address |
| `recipientAddress.address2` | `string` | City, state, country line |
| `paymentMethod` | `string` | Payment method label (e.g. `'PayPal'`) |
| `paymentId` | `string` | Payment transaction identifier |
| `items` | `array` | Line items — each `{ description: string, price: number }` |
| `totalPrice` | `string` | Aggregated total, pre-formatted as a decimal string (see helper below) |

## Price Aggregation Helper

Canonical pattern for invoice-style total calculation:

```js
const getTotalPrice = (items) =>
  items.reduce((total, item) => total + item.price, 0).toFixed(2);
```

- Input: `items[]` where each item has a numeric `price` field
- Output: `string` formatted to two decimal places (e.g. `"355.00"`)
- Called once per request; result passed as `totalPrice` into the template context

## Response Requirements

- `content-type` header MUST be `text/html` — Handlebars output is raw HTML, not JSON
- HTTP status: `200`
- Body: rendered HTML string returned directly from `template({ ...data })`

## Compile-Once Pattern

`Handlebars.compile(rawHtmlTemplate)` is expensive relative to per-request work. It MUST be called at module top-level (outside the event handler), not inside the `fetch` event handler. The compiled template function is reusable across requests. The `Handlebars.compile` cost is paid once during module initialization (when the module is wizened), not per request.

**Correct placement:**

```js
// Top-level — paid once at wizen time
const template = Handlebars.compile(htmlTemplate());

async function eventHandler() {
  const html = template({ cssStyles, logoBrand, ...invoiceData, totalPrice: getTotalPrice(invoiceData.items) });
  return new Response(html, { status: 200, headers: { 'content-type': 'text/html' } });
}
```

**Incorrect placement (do not do this):**

```js
async function eventHandler() {
  // Re-compiles the template on every request — wasteful
  const template = Handlebars.compile(htmlTemplate());
  ...
}
```

Note: the source example places `Handlebars.compile` inside `eventHandler`. The blueprint pattern above corrects this — always hoist `Handlebars.compile` to module top-level for production use.

## Complete index.js Pattern

```js
import Handlebars from 'handlebars';
import { cssStyles } from './css-styles.js';
import { htmlTemplate } from './html-template.js';
import { logoBrand } from './logo.js';

const invoiceData = {
  createdDate: 'March 4, 2024',
  dueDate: 'April 19, 2024',
  invoiceNumber: '1729',
  recipientAddress: {
    name: 'Homer Simpson',
    address1: '742 Evergreen Terrace',
    address2: 'Springfield, United States.',
  },
  paymentMethod: 'PayPal',
  paymentId: '8915648',
  items: [
    { description: '1x Keg of Duff Beer', price: 250 },
    { description: '3x Crate of Duff Beer', price: 85 },
    { description: '2x Duff Football Finger', price: 20 },
  ],
};

const getTotalPrice = (items) => items.reduce((total, item) => total + item.price, 0).toFixed(2);

const template = Handlebars.compile(htmlTemplate());

async function eventHandler() {
  const html = template({
    cssStyles,
    logoBrand,
    ...invoiceData,
    totalPrice: getTotalPrice(invoiceData.items),
  });

  return new Response(html, {
    status: 200,
    headers: { 'content-type': 'text/html' },
  });
}

addEventListener('fetch', (event) => {
  event.respondWith(eventHandler());
});
```

## Build Configuration

`package.json` build script:

```json
"build": "fastedge-build src/index.js dist/template-invoice.wasm"
```

Output binary: `dist/template-invoice.wasm`

## Constraints and Notes

- Template, CSS, and logo modules are pure JS string exports — no asset pipeline or `fastedge-assets` step is involved
- `invoiceData` in the source example is a static constant; in a real app, this would be sourced from the incoming request (query params, request body, or upstream fetch)
- `items[].price` must be numeric for `getTotalPrice` to produce a valid result
- `totalPrice` is a formatted string (`.toFixed(2)`), not a number — treat it as a display value only
- The source example calls `Handlebars.compile` inside `eventHandler`; the blueprint pattern hoists this to module top-level — the compile-once pattern is the correct production usage

## See Also

- http-base skeleton reference
- static-assets blueprint (contrast: uses asset pipeline, this blueprint does not)
- fastedge-build CLI reference
- FastEdge SDK JS reference
