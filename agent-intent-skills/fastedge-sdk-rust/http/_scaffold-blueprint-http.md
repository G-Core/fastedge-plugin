# HTTP Scaffold Blueprint Instructions

> For shared output format, cross-referencing rules, and exclusions see [_scaffold-blueprint-base.md](../_scaffold-blueprint-base.md)

This file adds HTTP-specific structure for scaffold blueprint intent skills in the `http/` directory.

### Required sections (in this order)

1. **When to Use** — 1-2 sentences describing when this blueprint should be selected. The agent uses this for matching against user intent.
2. **Dependencies to Add** — Only list dependencies that are **not already in the base skeleton's Cargo.toml**. Diff the example's Cargo.toml against the base skeleton to find what is new. Do not repeat base skeleton deps here.
3. **Files to Create** — complete content of any new files this feature adds.
4. **Files to Modify** — for each existing base skeleton file that needs changes:
   - `use` statements to add
   - Code to insert into the handler, with comments indicating placement
5. **Build Notes** — any special build steps, feature flags, or caveats
