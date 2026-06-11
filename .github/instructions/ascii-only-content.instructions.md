---
applyTo: "**/*"
description: "Enforce ASCII-only text to avoid Unicode/emoji issues in tooling and downstream endpoints (including AWS-integrated names/strings)."
---

For any new or modified text content in this repository:

1. Use ASCII characters only (`U+0000`-`U+007F`).
2. Do not introduce emoji.
3. Do not introduce Unicode punctuation/symbols in prose, comments, docs, or config values.
4. Prefer these replacements:
   - em dash/en dash -> `-`
   - right arrow -> `->`
   - curly quotes -> straight quotes `'` and `"`
   - ellipsis -> `...`
   - check/cross glyphs -> `[done]` / `[x]`
5. For Terraform variables/outputs/resource names, module names, system identifiers, and endpoint-related strings: always keep values ASCII-safe.
6. If existing Unicode text is touched, normalize it to ASCII in the same change when practical.

Rationale:
- Some typing/parsing modules and downstream integrations can fail or behave inconsistently with Unicode characters.
- AWS endpoint workflows and naming surfaces are more reliable with ASCII-only text.
