---
applyTo: "**/*.tftest.hcl"
description: "Use when editing Terraform test files; enforce validation test intent and expected pass/fail semantics."
---

For Terraform test files:

1. Keep positive tests validating successful plans/applies.
2. Keep negative tests intentionally expecting plan/apply failures for invalid inputs.
3. Ensure test names clearly indicate valid vs invalid scenarios.
4. Keep test behavior aligned with README testing documentation.
5. Do not silently change test intent when refactoring module inputs.
