---
applyTo: "**/README.md"
description: "Use when editing README files to keep docs aligned with examples, tests, and Makefile behavior."
---

When changing README content:

1. Keep test-stage descriptions aligned with actual `make` and Terraform test behavior.
2. Ensure docs reflect functional vs readonly test paths where both exist.
3. Keep examples and documented inputs/outputs in sync with code.
4. If validation commands were run, report exact command outcomes.
