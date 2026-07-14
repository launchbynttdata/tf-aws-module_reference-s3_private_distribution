---
applyTo: "**/*.tf"
description: "Use when editing Terraform module/test files; enforce primitive-module standards and naming/testing conventions."
---

For Terraform changes in this repository:

1. This is a **reference architecture** module (composes multiple primitives). Read `.github/agents/reference-architecture-creator.agent.md` first. Also consult `.github/agents/primitive-module-creator.agent.md` for general standards.
2. Keep composition logic in `main.tf`; computed values and policy JSON in `locals.tf`.
3. Use descriptive resource labels, not `this`, in module-owned resources.
4. Prefer explicit variable validation and clear error messages.
5. Keep outputs and descriptions precise.
6. Ensure `README.md` and `examples/complete/` remain consistent with actual inputs/outputs.
