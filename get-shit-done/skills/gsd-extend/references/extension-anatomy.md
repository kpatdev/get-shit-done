<extension_anatomy>

## How Extensions Work

GSD extensions are markdown files that integrate into the GSD lifecycle. They follow the same meta-prompting patterns as built-in GSD components.

## Discovery Mechanism

When GSD needs a workflow, agent, reference, or template:

```bash
# 1. Check project extensions first
ls .planning/extensions/{type}/{name}.md 2>/dev/null

# 2. Check global extensions
ls ~/.claude/gsd-extensions/{type}/{name}.md 2>/dev/null

# 3. Fall back to built-in
ls ~/.claude/get-shit-done/{type}/{name}.md 2>/dev/null
```

First match wins. This allows project-specific overrides.

## Extension Lifecycle

**1. Creation** - User creates extension file with proper structure
**2. Validation** - GSD validates frontmatter and structure
**3. Registration** - Extension becomes discoverable
**4. Triggering** - Extension activates based on conditions
**5. Execution** - Extension content is loaded and processed
**6. Completion** - Extension produces expected output

## Integration Points

Extensions integrate with GSD at specific hook points:

| Hook Point | What Happens | Extension Types |
|------------|--------------|-----------------|
| `pre-planning` | Before phase planning begins | workflows, references |
| `post-planning` | After plans created | workflows, agents |
| `pre-execution` | Before task execution | workflows, references |
| `post-execution` | After task completes | workflows, templates |
| `verification` | During verification phase | agents, workflows |
| `decision` | At decision checkpoints | agents, references |
| `always` | Whenever type is loaded | references |

## Content Model

All extensions follow the GSD content model:

```
┌─────────────────────────────────────┐
│ YAML Frontmatter                    │
│ - name, description                 │
│ - type-specific fields              │
├─────────────────────────────────────┤
│ XML Structure                       │
│ - Semantic containers               │
│ - Process steps (for workflows)     │
│ - Role definition (for agents)      │
│ - Content body (for references)     │
│ - Template format (for templates)   │
└─────────────────────────────────────┘
```

## File Naming

Extension filenames become their identifiers:

```
my-custom-workflow.md  →  triggers as "my-custom-workflow"
security-auditor.md    →  spawns as "security-auditor" agent
react-patterns.md      →  loads as "react-patterns" reference
api-spec.md           →  uses as "api-spec" template
```

Use kebab-case. Name should be descriptive of function.

## Scope Selection

**Use project scope (`.planning/extensions/`) when:**
- Extension is specific to this project
- Extension uses project-specific patterns
- Extension shouldn't affect other projects
- Extension is experimental

**Use global scope (`~/.claude/gsd-extensions/`) when:**
- Extension is generally useful across projects
- Extension represents your personal workflow preferences
- Extension is mature and tested
- Extension doesn't contain project-specific details

## Overriding Built-ins

To replace a built-in GSD component:

1. Create extension with same name as built-in
2. Place in project or global extensions directory
3. GSD will use your extension instead

Example: Override execute-plan workflow:
```
~/.claude/gsd-extensions/workflows/execute-plan.md
```

This completely replaces the built-in execute-plan.md for all projects.

**Warning:** Overriding built-ins requires deep understanding of GSD internals. Test thoroughly.

## Extension Dependencies

Extensions can reference other extensions or built-in components:

```markdown
<required_reading>
@~/.claude/get-shit-done/references/deviation-rules.md
@~/.claude/gsd-extensions/references/my-patterns.md
</required_reading>
```

Resolution order applies to @-references too.

</extension_anatomy>
