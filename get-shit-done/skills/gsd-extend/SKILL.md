---
name: gsd-extend
description: Create custom GSD approaches - complete methodologies with workflows, agents, references, and templates that work together. Use when users want to customize how GSD operates or add domain-specific execution patterns.
---

<essential_principles>

## GSD Extension System

GSD is extensible. Users can create custom **approaches** - complete methodologies that integrate with the GSD lifecycle.

An approach might include:
- **Workflow** - The execution pattern (required)
- **References** - Domain knowledge loaded during execution
- **Agent** - Specialized worker spawned by the workflow
- **Templates** - Output formats for artifacts

These components work together as a cohesive unit, not standalone pieces.

## Extension Resolution Order

```
1. .planning/extensions/{type}/     (project-specific - highest priority)
2. ~/.claude/gsd-extensions/{type}/ (global user extensions)
3. ~/.claude/get-shit-done/{type}/  (built-in GSD - lowest priority)
```

Project extensions override global, global overrides built-in.

## When to Create an Approach

**Planning alternatives:**
- Spike-first: Explore before formalizing
- Research-heavy: Deep investigation before any code
- Prototype-driven: Build throwaway code to learn

**Execution patterns:**
- TDD-strict: Enforce red-green-refactor cycle
- Security-first: Audit before each commit
- Performance-aware: Profile after each feature

**Domain-specific:**
- API development with OpenAPI-first workflow
- Game development with playtest checkpoints
- ML projects with experiment tracking

**Quality gates:**
- Accessibility review before UI completion
- Documentation requirements per feature
- Architecture review at phase boundaries

</essential_principles>

<routing>

## Understanding User Intent

Based on the user's message, route appropriately:

**Creating new approaches:**
- "create", "build", "add", "new approach/methodology/workflow"
  → workflows/create-approach.md

**Managing extensions:**
- "list", "show", "what extensions" → workflows/list-extensions.md
- "validate", "check" → workflows/validate-extension.md
- "remove", "delete" → workflows/remove-extension.md

**If intent is unclear:**

Ask using AskUserQuestion:
- header: "Action"
- question: "What would you like to do?"
- options:
  - "Create an approach" - Build a custom methodology (workflow + supporting pieces)
  - "List extensions" - See all installed extensions
  - "Remove an extension" - Delete something you've created

</routing>

<quick_reference>

## Approach Components

| Component | Purpose | Required? |
|-----------|---------|-----------|
| Workflow | Orchestrates the approach | Yes |
| References | Domain knowledge | Often |
| Agent | Specialized worker | Sometimes |
| Templates | Output formats | Sometimes |

## Directory Structure

```
~/.claude/gsd-extensions/
├── workflows/
│   └── spike-first-planning.md
├── references/
│   └── spike-patterns.md
├── agents/
│   └── spike-evaluator.md
└── templates/
    └── spike-summary.md
```

All components of an approach share a naming convention (e.g., `spike-*`).

## Scope Options

- **Project** (`.planning/extensions/`) - This project only
- **Global** (`~/.claude/gsd-extensions/`) - All projects

</quick_reference>

<reference_index>

## Domain Knowledge

All in `references/`:

| Reference | Content |
|-----------|---------|
| extension-anatomy.md | How extensions work, lifecycle, integration |
| workflow-structure.md | Workflow format with examples |
| agent-structure.md | Agent format with examples |
| reference-structure.md | Reference format with examples |
| template-structure.md | Template format with examples |
| validation-rules.md | Validation rules for all types |

</reference_index>

<workflows_index>

## Workflows

| Workflow | Purpose |
|----------|---------|
| create-approach.md | Create a complete methodology through conversation |
| list-extensions.md | Discover all installed extensions |
| validate-extension.md | Check extension for errors |
| remove-extension.md | Delete an extension |

</workflows_index>

<success_criteria>

Approach created successfully when:
- [ ] All components exist and are wired together
- [ ] Workflow references its supporting pieces correctly
- [ ] Components pass validation
- [ ] Approach is discoverable via list-extensions
- [ ] User understands how to trigger the approach

</success_criteria>
