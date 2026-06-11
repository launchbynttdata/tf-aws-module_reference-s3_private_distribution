---
applyTo: "tests/**/*.go"
description: "Use when editing post-deploy or Terratest Go files; enforce specific-value assertions and functional/readonly separation."
---

For Go tests in `tests/`:

1. Read `.github/agents/primitive-module-creator.agent.md` before editing.
2. Assert specific expected values when known (type, service name, IDs), not only non-empty checks.
3. Keep functional and readonly test entrypoints intentionally distinct.
4. Use read-only verification for readonly paths and write probes only in functional paths.
5. Add retry/wait logic when cloud eventual consistency can cause flakiness.
