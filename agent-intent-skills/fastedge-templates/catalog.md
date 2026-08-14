# Synthesis Instructions: catalog.md

> For shared cross-referencing rules, extraction rules, and exclusions see
> [_docs-pattern-base.md](./_docs-pattern-base.md)

## Target file
`plugins/gcore-fastedge/skills/fastedge-docs/reference/templates/catalog.md`

## Audience
An agent that is about to help a developer hand-build something FastEdge already ships as a
ready-made template — SSO, MFA, cookie hardening, HTML-to-Markdown conversion, or whatever new
templates get added. The point of this file is to get read **before** that code gets written.

## Output goal
One entry per template, each headed by an `##` section whose title includes the problem-domain
keywords a developer would actually say (not just the template's product name) — so a search
for "SSO", "login", "TOTP", "MFA", "two-factor", "secure cookies", etc. lands on the right
section. State plainly, near the top of each entry, that this exists so it should be used or
adapted instead of hand-building the same capability from scratch — and say why (it is already
built, tested, and handles the security-sensitive parts a hand-rolled version would need to get
right independently).

## Required content, per template

For every entry in the source `sources.catalog.files` list:

1. **Section heading** — template name plus the problem-domain terms a developer would search
   for (e.g. `## edge-sso — SSO / login / identity federation (Google, GitHub, Microsoft,
   Facebook, SAML)`).
2. **What it solves** — one or two sentences, specific enough that a developer mid-way through
   writing the same thing recognizes it.
3. **How it deploys** — which FastEdge app type(s) (HTTP app / CDN Proxy-WASM / both), and that
   deployment is via the Gcore portal template gallery (**not** `/gcore-fastedge:scaffold` or
   `/gcore-fastedge:deploy`).
4. **Runtime variants**, if the template has them (e.g. edge-sso's `SSO_VARIANT`: gate-only /
   cookie / header; edge-totp's Profile A / B) — one line each, what each mode means for what the
   origin has to do.
5. **Origin integration** — if (and only if) this template has an `<template>-integration` source
   entry in the manifest, say so explicitly and point at "the `<template-name>` integration
   reference" (by descriptive term, per the cross-referencing rule) for the customer-side wiring
   contract. If it doesn't have one (e.g. config-only templates), say the template is configured
   entirely through env vars/secrets with no origin code required.

## Structure

```
# FastEdge Bolt-On Templates

<one-paragraph framing: check this before hand-building auth, cookie-hardening, or
content-transform filters — these are maintained, tested apps, not starting points to copy>

## <template-1> — <problem-domain keywords>
...

## <template-2> — <problem-domain keywords>
...
```

## What to exclude
- Anything from `.env.example` files (env var reference belongs in the integration doc, not the
  catalog — the catalog is a discovery/recommendation surface, not a config reference)
- Build/CI/publish details

## Quality bar
If a new template's `catalog` files entry appears in the manifest with no prior corresponding
section in this file, generate a new section for it — do not require a human to ask. If a
template is removed from the manifest, remove its section.
