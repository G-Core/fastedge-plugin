<!--
  auto-updated: true
  sources:
    - id: fastedge-sdk-js
      ref: main
      commit: 81145a9a43ec499240c687bd49376ab20c72b11c
      updated: 2026-08-20
-->

---
type: feature
app_type: http
languages: [javascript]
capabilities: [templating, html, handlebars, ab-testing]
base_skeleton: http-base
source_example: FastEdge-sdk-js/examples/template-invoice-ab-testing
---

# Feature Blueprint: template-invoice-ab-testing

## When to Use

Use this blueprint when you need to render HTML templates with per-request A/B test variants (alternative logos, fonts, layouts) selected by upstream-assigned request headers, while keeping the Handlebars rendering pipeline otherwise unchanged. Variant assignment is delegated to the caller — an upstream load-balancer or proxy sets the test headers; this blueprint renders the appropriate variant rather than choosing it. Pairs naturally with an upstream A/B routing layer.

## Dependencies to Add

```json
"handlebars": "^4.7.9"
```

Already provided by the http-base skeleton (via `@gcoredev/fastedge-sdk-js`): `addEventListener`, `Request`, `Response`.

## Source Modules

This feature requires three helper modules alongside `src/index.js`. The generator must extract complete contents from the source example:

| Module | Export | Signature | Description |
|---|---|---|---|
| `src/css-styles.js` | `getStyles` | `getStyles(font: string \| null): string` | Returns variant-specific CSS string based on the font variant value |
| `src/html-template.js` | `htmlTemplate` | `htmlTemplate(font: string \| null): string` | Returns the raw Handlebars HTML template string for the given font variant |
| `src/logo.js` | `getLogoBrand` | `getLogoBrand(isBottle: boolean): string` | Returns the variant-specific logo markup/string; `true` → bottle logo, `false` → default logo |

Each module accepts the relevant variant input and returns a variant-specific string.

## Variant Inputs

Variants are selected exclusively from request headers. No cookie handling.

| Header | Type | Values | Used By |
|---|---|---|---|
| `ab-test-logo` | `string \| null` | `"bottle"` → bottle logo; any other value → default logo | `getLogoBrand(isBottle)` |
| `ab-test-font` | `string \| null` | Arbitrary font variant string; passed directly to style and template helpers | `getStyles(font)`, `htmlTemplate(font)` |

Reading variant headers:

```javascript
const isAbTestLogo = request.headers.get('ab-test-logo') === 'bottle';
const abTestFont = request.headers.get('ab-test-font');
```

## Rendering Pipeline (Ordered)

1. Read variant headers from `request`: `isAbTestLogo` (boolean), `abTestFont` (string or null)
2. Resolve `logo` string via `getLogoBrand(isAbTestLogo)`
3. Resolve `cssStyles` string via `getStyles(abTestFont)`
4. Resolve `rawHtmlTemplate` string via `htmlTemplate(abTestFont)`
5. Compile Handlebars template: `const template = Handlebars.compile(rawHtmlTemplate)`
6. Render: `const html = template({ cssStyles, logo, ...invoiceData, totalPrice })`
7. Return `new Response(html, { status: 200, headers: { 'content-type': 'text/html' } })`

## Template Data Shape

The object passed to `template(...)`:

```javascript
{
  cssStyles,           // string — variant CSS from getStyles()
  logo,                // string — variant logo from getLogoBrand() (field name: "logo")
  ...invoiceData,      // spread of the invoice data object (see Invoice Data Shape below)
  totalPrice,          // string — computed from invoiceData.items
}
```

Note: the logo field is named `logo` (not `logoBrand`).

## Invoice Data Shape

```javascript
const invoiceData = {
  createdDate: string,           // e.g. 'March 4, 2024'
  dueDate: string,               // e.g. 'April 19, 2024'
  invoiceNumber: string,         // e.g. '1729'
  recipientAddress: {
    name: string,
    address1: string,
    address2: string,
  },
  paymentMethod: string,         // e.g. 'PayPal'
  paymentId: string,             // e.g. '8915648'
  items: Array<{
    description: string,
    price: number,
  }>,
};
```

## Total Price Computation

```javascript
const getTotalPrice = (items) =>
  items.reduce((total, item) => total + item.price, 0).toFixed(2);
```

- Input: `items` array from `invoiceData`
- Returns: `string` (fixed two decimal places)
- Passed to template as `totalPrice`

## Event Handler Signature

```javascript
async function eventHandler({ request })
```

- Destructures `request` from the fetch event
- Returns: `Promise<Response>`

## Response

| Field | Value |
|---|---|
| Status | `200` |
| `content-type` header | `text/html` |
| Body | Rendered Handlebars HTML string |

## Entry Point Structure

```javascript
import Handlebars from 'handlebars';
import { getStyles } from './css-styles.js';
import { htmlTemplate } from './html-template.js';
import { getLogoBrand } from './logo.js';

// invoiceData constant (static or externalized)
// getTotalPrice helper

async function eventHandler({ request }) {
  const isAbTestLogo = request.headers.get('ab-test-logo') === 'bottle';
  const logo = getLogoBrand(isAbTestLogo);

  const abTestFont = request.headers.get('ab-test-font');
  const cssStyles = getStyles(abTestFont);

  const rawHtmlTemplate = htmlTemplate(abTestFont);
  const template = Handlebars.compile(rawHtmlTemplate);

  const html = template({
    cssStyles,
    logo,
    ...invoiceData,
    totalPrice: getTotalPrice(invoiceData.items),
  });

  return new Response(html, {
    status: 200,
    headers: { 'content-type': 'text/html' },
  });
}

addEventListener('fetch', (event) => {
  event.respondWith(eventHandler(event));
});
```

## Build Configuration

```json
{
  "name": "fastedge-example-template-invoice-ab-testing",
  "type": "module",
  "scripts": {
    "build": "fastedge-build src/index.js dist/template-invoice-ab-testing.wasm"
  },
  "dependencies": {
    "@gcoredev/fastedge-sdk-js": "^2.3.0",
    "handlebars": "^4.7.9"
  }
}
```

## Constraints and Notes

- Variant assignment is the responsibility of the upstream caller (load-balancer, proxy, or CDN routing rule). This blueprint only renders — it does not select or assign test groups.
- Variants are driven exclusively by request headers (`ab-test-logo`, `ab-test-font`). There is no cookie-based variant selection.
- `handlebars` is a third-party npm dependency and must be declared explicitly; it is not bundled with the http-base skeleton.
- `type: "module"` is required for ES module imports.
- `invoiceData` in this example is a static constant. Replace with dynamic data retrieval as needed for production use.
- All three helper modules (`css-styles.js`, `html-template.js`, `logo.js`) must be present; the generator must copy their complete contents from the source example.

## See Also

- template-invoice (non-AB variant, single rendering path)
- http-base skeleton (base event handler structure and build setup)
- fastedge-build CLI reference (WASM compilation)
- Handlebars documentation (template syntax and compilation API)

## Source Material

### FILE: examples/template-invoice-ab-testing/src/index.js

```javascript
import Handlebars from 'handlebars';

import { getStyles } from './css-styles.js';
import { htmlTemplate } from './html-template.js';
import { getLogoBrand } from './logo.js';

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
    {
      description: '1x Keg of Duff Beer',
      price: 250,
    },
    {
      description: '3x Crate of Duff Beer',
      price: 85,
    },
    {
      description: '2x Duff Football Finger',
      price: 20,
    },
  ],
};

const getTotalPrice = (items) => items.reduce((total, item) => total + item.price, 0).toFixed(2);

async function eventHandler({ request }) {
  const isAbTestLogo = request.headers.get('ab-test-logo') === 'bottle';
  const logo = getLogoBrand(isAbTestLogo);

  const abTestFont = request.headers.get('ab-test-font');
  const cssStyles = getStyles(abTestFont);

  const rawHtmlTemplate = htmlTemplate(abTestFont);
  const template = Handlebars.compile(rawHtmlTemplate);

  const html = template({
    cssStyles,
    logo,
    ...invoiceData,
    totalPrice: getTotalPrice(invoiceData.items),
  });

  return new Response(html, {
    status: 200,
    headers: {
      'content-type': 'text/html',
    },
  });
}

addEventListener('fetch', (event) => {
  event.respondWith(eventHandler(event));
});
```

### FILE: examples/template-invoice-ab-testing/package.json

```json
{
  "name": "fastedge-example-template-invoice-ab-testing",
  "version": "1.0.0",
  "description": "FastEdge JS example: Handlebars invoice with A/B test header variants",
  "type": "module",
  "scripts": {
    "build": "fastedge-build src/index.js dist/template-invoice-ab-testing.wasm"
  },
  "dependencies": {
    "@gcoredev/fastedge-sdk-js": "^2.3.0",
    "handlebars": "^4.7.9"
  }
}
```
