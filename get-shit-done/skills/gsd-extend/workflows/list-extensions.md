<purpose>
Discover and list all GSD extensions, grouped by approach when components share naming conventions.
</purpose>

<process>

<step name="scan_extensions">
Scan all extension locations:

```bash
echo "Scanning extensions..."

# Collect all extension files
PROJECT_EXTS=$(find .planning/extensions -name "*.md" 2>/dev/null | sort)
GLOBAL_EXTS=$(find ~/.claude/gsd-extensions -name "*.md" 2>/dev/null | sort)
BUILTIN_WORKFLOWS=$(ls ~/.claude/get-shit-done/workflows/*.md 2>/dev/null | wc -l | xargs)
BUILTIN_REFS=$(ls ~/.claude/get-shit-done/references/*.md 2>/dev/null | wc -l | xargs)
BUILTIN_TEMPLATES=$(ls ~/.claude/get-shit-done/templates/*.md 2>/dev/null | wc -l | xargs)
```
</step>

<step name="identify_approaches">
Group extensions by shared prefix to identify approaches:

For each extension file:
1. Extract the base name (e.g., `spike-first-planning.md` → `spike-first`)
2. Group files with same prefix across types
3. Identify cohesive approaches vs standalone components

```bash
# Example grouping logic
for ext in $GLOBAL_EXTS; do
  type=$(dirname "$ext" | xargs basename)
  name=$(basename "$ext" .md)
  prefix=$(echo "$name" | sed 's/-[^-]*$//')  # Remove last segment
  echo "$prefix|$type|$name"
done | sort
```
</step>

<step name="format_output">
Present extensions organized by scope and approach:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 GSD ► EXTENSIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Project Extensions (.planning/extensions/)

{If none:}
None installed.

{If found, group by approach:}

### spike-first (approach)
- workflows/spike-first-planning.md
- references/spike-patterns.md
- agents/spike-evaluator.md

### security-audit (standalone workflow)
- workflows/security-audit.md

───────────────────────────────────────────────────────────────

## Global Extensions (~/.claude/gsd-extensions/)

{Same format}

───────────────────────────────────────────────────────────────

## Built-in GSD

- {N} workflows
- {N} references
- {N} templates
- {N} agents

───────────────────────────────────────────────────────────────

## Override Status

{List any custom extensions that override built-ins}

───────────────────────────────────────────────────────────────

## Actions

/gsd:extend create    — Create a new approach
/gsd:extend remove X  — Remove an extension

───────────────────────────────────────────────────────────────
```
</step>

<step name="detail_on_request">
If user asks about a specific extension, show details:

```bash
# Read frontmatter
head -20 "$EXT_PATH" | sed -n '/^---$/,/^---$/p'

# Show structure
wc -l "$EXT_PATH"

# Show cross-references
grep -oE '@[~./][^[:space:]]+' "$EXT_PATH"
```

Present:
```
## Extension: {name}

**Type:** {workflow/agent/reference/template}
**Location:** {path}
**Description:** {from frontmatter}

**Cross-references:**
{list of @-references}

**Structure:**
{line count, sections present}
```
</step>

</process>

<success_criteria>
- [ ] All scopes scanned (project, global, built-in)
- [ ] Extensions grouped by approach where applicable
- [ ] Override status identified
- [ ] User knows how to create/remove
</success_criteria>
