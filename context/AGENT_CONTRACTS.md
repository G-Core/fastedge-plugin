# Agent & Trigger Contracts

Defines the input/output interfaces for pipeline agents and workflow triggers. Read this when modifying `invoke-agent.sh`, `manage-pr.sh`, or the workflow trigger configuration.

> **Historical reference**: Migrated from `specs/001-auto-ref-update/contracts/`. For the original speckit files, check git history at or before commit `725c3e0`.

---

## Generator Agent Contract

**Purpose**: Transform fetched source content into updated reference documentation.

**Implementation**: Claude Code CLI via `claude -p` (see `PIPELINE_DESIGN_DECISIONS.md` §1).

### Required Inputs

Passed as a structured prompt containing all of the following:

| Input | Description |
|-------|-------------|
| Existing reference file content | The current content of the reference file (or section if `section` is set) |
| Fetched source content | All files from the sparse checkout, concatenated with filename headers |
| Synthesis intent | If an intent file exists for this reference file, injected as `## Synthesis Instructions` |
| Section scope | If `section` is set: agent MUST update only that named section, leaving all other content verbatim |
| Traceability metadata | `source_repo_id`, `ref`, `commit`, `updated` — to be written as frontmatter |
| Output format instruction | Agent MUST return the complete updated file (or section) content, nothing else |

### Expected Output

1. Valid Markdown with traceability frontmatter at the top (for full-file updates)
2. Only the updated section content (for section-scoped updates — frontmatter is added by the script)
3. No explanation text, no preamble, no commentary — only the document content

### Output Validation (performed by script before passing to reviewer)

- Non-empty content
- Traceability frontmatter block present and parseable (full-file updates only)
- Content differs from existing file/section (if identical, skip — no PR needed)

---

## Section Splice Contract

When `section` is set, the splice role in `invoke-agent.sh` is responsible for splicing the generator's output back into the full reference file.

**Rules**:

1. Locate the section boundary by matching the heading `## <section>` (case-sensitive)
2. Identify the end of that section as either the next `##`-level heading or end-of-file
3. Replace only the content between those boundaries with the generator's output
4. Preserve all other sections verbatim
5. Update the traceability frontmatter to reflect the new commit SHA and date for the contributing repo, while preserving existing entries for other repos

**Heading drift**: If the section heading is not found in the existing file, the script MUST fail loudly (`exit 1`) rather than appending or overwriting the full file. This forces an explicit human decision when source repo restructuring causes section names to diverge.

---

## Reviewer Agent Contract

**Purpose**: Evaluate the generator agent's output for quality, accuracy, and compliance.

**Implementation**: OpenAI `gpt-4o` via `https://api.openai.com/v1/chat/completions` (curl + jq). Auth: `OPENAI_API_KEY`.

### Required Inputs

| Input | Description |
|-------|-------------|
| Generator's output | The complete proposed content (file or section) |
| Source material | The fetched source files used to generate it |
| Review criteria | The criteria below, embedded verbatim in the prompt |
| Traceability block | The frontmatter from the output — reviewer must validate it |

**Review criteria embedded in prompt**:
```
Evaluate the proposed reference document update against these criteria:
1. Accuracy: Does the content correctly reflect the source material?
2. Completeness: Are all public API signatures, parameters, return types, and constraints present?
3. Agent-consumability: Is the content precise and structured for AI consumption (no vague prose, no marketing language)?
4. Traceability: Is the frontmatter block present, correctly formatted, and does the commit SHA match the source? Note: the `ref` field is the git tag used for the sparse checkout — do NOT compare it against any version field in package.json or Cargo.toml. Those are npm/crate release versions and are unrelated to the git tag.
5. Scope compliance: If a section was specified, does the update touch ONLY that section?
```

### Expected Output

```
VERDICT: ACCEPT
FINDINGS: <one paragraph, or "None." if no issues>
```

or

```
VERDICT: REJECT
FINDINGS: <specific issues found, referenced by section or line>
```

**Parsing rule**: The script extracts `VERDICT:` value (case-insensitive match for `ACCEPT` or `REJECT`) and everything after `FINDINGS:` as the findings text. Any other format causes the step to fail with an error.

**Behaviour based on verdict**:
- `ACCEPT`: proceed to write files to `plugins/` and open/update PR without `needs-review` label
- `REJECT`: proceed to open/update PR WITH `needs-review` label; findings appear in PR body

---

## Script Invocation Interface

`scripts/sync/invoke-agent.sh` is called by the main workflow:

```bash
invoke-agent.sh \
  --role generator|reviewer|splice \
  --agent claude|openai \
  --prompt-file /path/to/prompt.md \
  --output-file /path/to/output.md
```

### Exit Codes

| Exit Code | Meaning |
|-----------|---------|
| `0` | Agent responded with parseable output |
| `1` | Agent invocation failed (API error, timeout, empty response) |
| `2` | Reviewer output did not match expected format (reviewer only) |

---

## Workflow Trigger Contracts

The `sync-reference-docs` workflow exposes two trigger interfaces.

### Trigger 1: Manual Dispatch (`workflow_dispatch`)

**Invoked by**: Any user with write access to the repo, via GitHub Actions UI or CLI.

```bash
gh workflow run sync-reference-docs.yml
gh workflow run sync-reference-docs.yml -f source_repo_id=fastedge-sdk-js
gh workflow run sync-reference-docs.yml -f dry_run=true
```

| Input | Type | Required | Description |
|-------|------|----------|-------------|
| `source_repo_id` | string | No | If set, process only this repo ID. If omitted, process all repos in `sources.json`. |
| `dry_run` | boolean | No | If `true`, run all steps but do not open/update PRs and do not update baseline tags. |

**Behaviour**: Processes repos whose `trigger` is `"schedule"` or `"both"`, plus any repo matching `source_repo_id` regardless of its trigger setting.

### Trigger 2: Repository Dispatch (`repository_dispatch`)

**Invoked by**: A source repository sending a `repository_dispatch` event to the `fastedge-plugin` repo.

**Required event type**: `fastedge-ref-update`

**Payload contract**:
```json
{
  "event_type": "fastedge-ref-update",
  "client_payload": {
    "source_repo_id": "fastedge-sdk-js",
    "ref": "v2.2.0",
    "commit": "abc1234def5678abc1234def5678abc1234def56"
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `source_repo_id` | string | Yes | Must match an `id` in `sources.json`. Unknown IDs cause a validation failure. |
| `ref` | string | Yes | The release tag or branch ref that triggered the dispatch. |
| `commit` | string | Yes | Full 40-character commit SHA at that ref. |

**Behaviour**: Processes only the repo identified by `source_repo_id`. Repos with `trigger: "schedule"` are not processed even if listed in `sources.json`.

**How source repos send the event**:
```bash
curl -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $FASTEDGE_PLUGIN_DISPATCH_TOKEN" \
  https://api.github.com/repos/G-Core/fastedge-plugin/dispatches \
  -d '{
    "event_type": "fastedge-ref-update",
    "client_payload": {
      "source_repo_id": "fastedge-sdk-js",
      "ref": "v2.2.0",
      "commit": "abc1234..."
    }
  }'
```

The dispatch token (`FASTEDGE_PLUGIN_DISPATCH_TOKEN`) must be a PAT with `repo` scope stored as a secret in the source repo.

### Workflow Exit Codes

| Exit Code | Meaning |
|-----------|---------|
| `0` | All processed repos succeeded (or were legitimately skipped) |
| `1` | One or more repos failed; see step summary for details |

A non-zero exit makes the workflow run appear as "failed" in GitHub Actions — this is intentional (Principle XII: fail visibly).
