<purpose>
Remove an extension from project or global scope.
</purpose>

<process>

<step name="identify_extension">
If path not provided, list extensions and ask which to remove:

```bash
echo "=== Project Extensions ==="
ls .planning/extensions/*/*.md 2>/dev/null

echo ""
echo "=== Global Extensions ==="
ls ~/.claude/gsd-extensions/*/*.md 2>/dev/null
```

Use AskUserQuestion to select which extension to remove.
</step>

<step name="confirm_removal">
Before removing, show what will happen:

```
## Remove Extension: {name}

**Location:** {path}
**Type:** {workflow|agent|reference|template}

{If this extension overrides a built-in:}
**Note:** This extension overrides the built-in `{name}`.
After removal, GSD will use the built-in version.

{If this extension overrides a global extension:}
**Note:** This extension overrides a global extension.
After removal, the global version will be used.

**This action cannot be undone.**

Remove this extension?
```

Use AskUserQuestion:
- header: "Confirm"
- question: "Remove this extension?"
- options:
  - "Yes, remove it" - Delete the extension file
  - "No, keep it" - Cancel removal
</step>

<step name="remove_extension">
If confirmed, remove the extension:

```bash
rm "$EXT_PATH"
echo "Extension removed: $EXT_PATH"

# Check if directory is now empty
DIR=$(dirname "$EXT_PATH")
if [[ -z "$(ls -A $DIR 2>/dev/null)" ]]; then
  rmdir "$DIR"
  echo "Empty directory removed: $DIR"
fi
```
</step>

<step name="report_result">
Confirm removal:

```
## Extension Removed

**Name:** {name}
**Was at:** {path}

{If there's a fallback:}
**Now using:** {fallback path} (built-in | global)

{If no fallback:}
**Note:** No fallback exists. This functionality is no longer available.
```
</step>

</process>

<success_criteria>
- [ ] Extension identified
- [ ] User confirmed removal
- [ ] Extension file deleted
- [ ] Empty directories cleaned up
- [ ] Fallback status communicated
</success_criteria>
