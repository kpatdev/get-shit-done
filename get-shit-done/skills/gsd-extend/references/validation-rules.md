<validation_rules>

## Extension Validation

All extensions are validated before activation. Invalid extensions are skipped with warning.

## Common Validation Rules

**1. YAML Frontmatter**

Must be valid YAML between `---` markers:
```yaml
---
name: kebab-case-name
description: One sentence description
# type-specific fields...
---
```

**2. Required Fields by Type**

| Type | Required Fields |
|------|-----------------|
| Workflow | name, description, triggers |
| Agent | name, description, tools, spawn_from |
| Reference | name, description, load_when |
| Template | name, description, used_by |

**3. Name Validation**

- Must be kebab-case: `my-extension-name`
- Must match filename (without .md)
- No spaces or special characters
- 3-50 characters

**4. XML Structure**

If extension uses XML tags:
- Tags must be properly closed
- Nesting must be balanced
- No malformed tags

## Type-Specific Validation

### Workflows

```yaml
triggers:
  - plan-phase        # valid
  - execute-plan      # valid
  - execute-phase     # valid
  - verify-phase      # valid
  - custom            # valid
  - invalid-trigger   # INVALID
```

**Must have:**
- At least one valid trigger
- `<process>` section with `<step>` elements
- `<success_criteria>` section

### Agents

```yaml
tools:
  - Read              # valid
  - Write             # valid
  - Edit              # valid
  - Bash              # valid
  - Grep              # valid
  - Glob              # valid
  - WebFetch          # valid
  - WebSearch         # valid
  - mcp__context7__*  # valid (MCP tools)
  - InvalidTool       # INVALID
```

**Must have:**
- At least one valid tool
- `<role>` section
- `<output_format>` section

### References

```yaml
load_when:
  - keyword           # valid - loads when keyword appears
  - "*-auth-*"        # valid - glob pattern
  - always            # valid - always loads (use sparingly)
  - ""                # INVALID - empty keyword
```

**Must have:**
- At least one load_when keyword
- Content body (not empty)

### Templates

```yaml
used_by:
  - workflow-name     # should reference real workflow
  - agent-name        # should reference real agent
```

**Must have:**
- `<template>` section with actual template content
- `<guidelines>` section explaining placeholders

## Validation Commands

```bash
# Validate a single extension
/gsd:extend validate {path}

# Validate all extensions
/gsd:extend validate --all
```

## Error Messages

| Error | Cause | Fix |
|-------|-------|-----|
| "Invalid YAML frontmatter" | Malformed YAML | Check indentation and syntax |
| "Missing required field: {field}" | Field not present | Add the required field |
| "Invalid trigger: {trigger}" | Unknown trigger name | Use valid trigger name |
| "Invalid tool: {tool}" | Unknown tool name | Use valid tool name |
| "Unbalanced XML tags" | Missing closing tag | Close all opened tags |
| "Name doesn't match filename" | name: foo but file is bar.md | Make them match |

## Self-Validation

Extensions should self-validate by:

1. Including comprehensive examples
2. Testing with real usage
3. Documenting edge cases

Good extension authors test their extensions before sharing.

</validation_rules>
