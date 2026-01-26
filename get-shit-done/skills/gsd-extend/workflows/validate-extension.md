<purpose>
Validate an extension file for errors before activation.
</purpose>

<required_reading>
@~/.claude/get-shit-done/skills/gsd-extend/references/validation-rules.md
</required_reading>

<process>

<step name="identify_extension">
If path not provided, scan for extensions and ask which to validate:

```bash
echo "Available extensions:"
ls .planning/extensions/*/*.md 2>/dev/null
ls ~/.claude/gsd-extensions/*/*.md 2>/dev/null
```

Use AskUserQuestion to select if multiple found.
</step>

<step name="determine_type">
Determine extension type from path:

```bash
# Extract type from path
TYPE=$(dirname "$EXT_PATH" | xargs basename)
# workflows, agents, references, or templates
```
</step>

<step name="validate_frontmatter">
Check YAML frontmatter:

```bash
# Extract frontmatter
sed -n '1,/^---$/p' "$EXT_PATH" | tail -n +2 | head -n -1 > /tmp/frontmatter.yaml

# Check for required fields based on type
case $TYPE in
  workflows)
    grep -q "^name:" /tmp/frontmatter.yaml && echo "✓ name" || echo "✗ name missing"
    grep -q "^description:" /tmp/frontmatter.yaml && echo "✓ description" || echo "✗ description missing"
    grep -q "^triggers:" /tmp/frontmatter.yaml && echo "✓ triggers" || echo "✗ triggers missing"
    ;;
  agents)
    grep -q "^name:" /tmp/frontmatter.yaml && echo "✓ name" || echo "✗ name missing"
    grep -q "^description:" /tmp/frontmatter.yaml && echo "✓ description" || echo "✗ description missing"
    grep -q "^tools:" /tmp/frontmatter.yaml && echo "✓ tools" || echo "✗ tools missing"
    ;;
  references)
    grep -q "^name:" /tmp/frontmatter.yaml && echo "✓ name" || echo "✗ name missing"
    grep -q "^description:" /tmp/frontmatter.yaml && echo "✓ description" || echo "✗ description missing"
    grep -q "^load_when:" /tmp/frontmatter.yaml && echo "✓ load_when" || echo "✗ load_when missing"
    ;;
  templates)
    grep -q "^name:" /tmp/frontmatter.yaml && echo "✓ name" || echo "✗ name missing"
    grep -q "^description:" /tmp/frontmatter.yaml && echo "✓ description" || echo "✗ description missing"
    grep -q "^used_by:" /tmp/frontmatter.yaml && echo "✓ used_by" || echo "✗ used_by missing"
    ;;
esac
```
</step>

<step name="validate_name_match">
Check that name field matches filename:

```bash
FILENAME=$(basename "$EXT_PATH" .md)
NAME=$(grep "^name:" /tmp/frontmatter.yaml | cut -d: -f2 | xargs)

if [[ "$FILENAME" == "$NAME" ]]; then
  echo "✓ Name matches filename"
else
  echo "✗ Name mismatch: frontmatter says '$NAME' but file is '$FILENAME.md'"
fi
```
</step>

<step name="validate_xml_structure">
Check XML tag balance:

```bash
# Count opening and closing tags
OPEN_TAGS=$(grep -oE '<[a-z_]+[^/>]*>' "$EXT_PATH" | wc -l)
CLOSE_TAGS=$(grep -oE '</[a-z_]+>' "$EXT_PATH" | wc -l)
SELF_CLOSE=$(grep -oE '<[a-z_]+[^>]*/>' "$EXT_PATH" | wc -l)

echo "Opening tags: $OPEN_TAGS"
echo "Closing tags: $CLOSE_TAGS"
echo "Self-closing: $SELF_CLOSE"

if [[ "$OPEN_TAGS" -eq "$CLOSE_TAGS" ]]; then
  echo "✓ XML tags balanced"
else
  echo "✗ XML tags unbalanced"
fi
```
</step>

<step name="validate_references">
Check that @-references point to existing files:

```bash
grep -oE '@[~./][^[:space:]]+' "$EXT_PATH" | while read ref; do
  # Expand ~ to home
  path="${ref#@}"
  path="${path/#\~/$HOME}"

  if [[ -f "$path" ]]; then
    echo "✓ Reference exists: $ref"
  else
    echo "✗ Reference missing: $ref"
  fi
done
```
</step>

<step name="type_specific_validation">
Run type-specific validation:

**Workflows:**
- Check triggers are valid values
- Check `<process>` section exists
- Check `<step>` elements present

**Agents:**
- Check tools are valid tool names
- Check `<role>` section exists
- Check `<output_format>` section exists

**References:**
- Check load_when has at least one keyword
- Check content body is not empty

**Templates:**
- Check `<template>` section exists
- Check `<guidelines>` section exists
</step>

<step name="report_results">
Present validation results:

```
## Validation Report: {extension_name}

**Type:** {type}
**Location:** {path}

### Frontmatter
{results}

### Structure
{results}

### References
{results}

### Type-Specific
{results}

---

**Status:** {VALID | INVALID}

{If invalid:}
**Issues to fix:**
1. {issue}
2. {issue}
```
</step>

</process>

<success_criteria>
- [ ] Extension file found and read
- [ ] Frontmatter validated
- [ ] Name/filename match checked
- [ ] XML structure validated
- [ ] References validated
- [ ] Type-specific checks run
- [ ] Clear report provided
</success_criteria>
