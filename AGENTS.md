# AGENTS.md

## Purpose

This repository demonstrates how to route coding assistants (Copilot, Claude, and others) toward the canonical Terraform primitive module guidance used by this team.

## Primary Guidance Sources

- `.github/agents/primitive-module-creator.agent.md` (canonical primitive module standard)
- `.github/agents/reference-architecture-creator.agent.md` (composition/testing depth reference)

When guidance conflicts, follow explicit user instructions first, then document the override.

## Required Workflow

1. Read the target file and the relevant `.github/instructions/*.instructions.md` file.
2. Read `.github/agents/primitive-module-creator.agent.md` before making Terraform or Terratest changes.
3. Keep changes scoped; avoid unrelated refactors.
4. Update tests and docs when behavior changes.
5. Run validation commands (`make lint`, `make test`) before finalizing.

## Blocking Review Checklist

- [ ] No Terraform resource blocks named `this` in new/modified code unless explicitly required by an upstream module.
- [ ] Post-deploy tests assert specific expected values (not only non-empty values).
- [ ] Functional and readonly test paths are distinct and intentionally different.
- [ ] README testing section matches actual Makefile/test behavior.
- [ ] `make lint` and `make test` were executed, or limitations are explicitly documented.
