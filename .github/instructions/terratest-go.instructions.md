---
applyTo: "tests/**/*.go"
description: "Use when editing post-deploy or Terratest Go files; enforce specific-value assertions and functional/readonly separation."
---

For Go tests in `tests/`:

1. This is a **reference architecture** module. Read `.github/agents/reference-architecture-creator.agent.md` before editing. Also consult `.github/agents/primitive-module-creator.agent.md` for general standards.
2. Assert specific expected values when known (type, service name, IDs), not only non-empty checks.
3. Keep functional and readonly test entrypoints intentionally distinct.
4. Use read-only verification for readonly paths and write probes only in functional paths.
5. Add retry/wait logic when cloud eventual consistency can cause flakiness.
6. When validating AWS VPCE DNS names (wildcard format `*.vpce-...`), strip the `*.` prefix with `strings.TrimPrefix(n, "*.")` before extracting the first label for regex matching.
