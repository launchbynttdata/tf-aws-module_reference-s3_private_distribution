---
applyTo: "**/*.tf"
description: "Use when editing Terraform module/test files; enforce primitive-module standards and naming/testing conventions."
---

For Terraform changes in this repository:

1. Read `.github/agents/primitive-module-creator.agent.md` first.
2. Keep primitive scope to a single resource type per module.
3. Use descriptive resource labels, not `this`, in module-owned resources.
4. Prefer explicit variable validation and clear error messages.
5. Keep outputs and descriptions precise.
6. Ensure `README.md` and `examples/complete/` remain consistent with actual inputs/outputs.
