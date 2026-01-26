<purpose>
Create a complete GSD approach through conversational discovery. An approach is a cohesive methodology with a workflow and supporting components (references, agents, templates) that work together.
</purpose>

<required_reading>
@~/.claude/get-shit-done/skills/gsd-extend/references/extension-anatomy.md
@~/.claude/get-shit-done/skills/gsd-extend/references/workflow-structure.md
@~/.claude/get-shit-done/skills/gsd-extend/references/agent-structure.md
@~/.claude/get-shit-done/skills/gsd-extend/references/reference-structure.md
@~/.claude/get-shit-done/skills/gsd-extend/references/template-structure.md
</required_reading>

<process>

<step name="open_conversation">
Start with an open question to understand what the user wants to achieve.

Ask inline (freeform, NOT AskUserQuestion):

"What would you like GSD to do differently? Describe the approach or methodology you have in mind."

Wait for their response. This gives context for intelligent follow-up.
</step>

<step name="explore_the_approach">
Based on their response, explore what they're describing. Use AskUserQuestion to clarify:

**Understand the trigger:**
- When should this approach activate?
- Does it replace something built-in or add new capability?

**Understand the flow:**
- What happens first? Then what?
- Are there decision points?
- What verification happens?

**Understand the expertise:**
- What domain knowledge is needed?
- Is there specialized analysis required?
- What patterns should be followed/avoided?

**Understand the output:**
- What artifacts are produced?
- Are there specific formats required?
- How does it integrate with existing GSD artifacts?

Ask follow-up questions naturally. Don't interrogate - collaborate.

Example questions:
- "When you say X, do you mean A or B?"
- "Walk me through what happens after Y"
- "What makes this different from the default GSD flow?"
- "What knowledge would Claude need to do this well?"
</step>

<step name="identify_components">
Based on the conversation, identify what components are needed:

**Workflow (always needed):**
- What's the sequence of steps?
- What triggers it? (plan-phase, execute-plan, verify-phase, custom)
- Does it replace a built-in or run alongside?

**References (if domain knowledge needed):**
- What patterns/practices should be known?
- What anti-patterns should be avoided?
- Is there project-specific context?

**Agent (if specialized work needed):**
- Is there analysis that requires focus?
- Would a dedicated worker improve quality?
- What tools would it need?

**Template (if structured output needed):**
- Are there specific artifacts to produce?
- Is consistent formatting important?
- What placeholders are needed?

Present the component plan:

```
## Proposed Approach: {name}

Based on our conversation, here's what I'll create:

**Workflow:** {name}-workflow.md
- Triggers: {triggers}
- Replaces: {replaces or "Nothing (new capability)"}
- Steps: {brief description of flow}

{If reference needed:}
**Reference:** {name}-patterns.md
- Contains: {what knowledge}
- Loaded when: {triggers}

{If agent needed:}
**Agent:** {name}-agent.md
- Purpose: {what it does}
- Tools: {tools}
- Spawned by: {when}

{If template needed:}
**Template:** {name}-template.md
- Produces: {what artifact}
- Used by: {workflow/agent}

Does this capture your approach? Anything to add or change?
```

Wait for confirmation or iterate.
</step>

<step name="determine_scope">
Ask where the approach should live:

- header: "Scope"
- question: "Where should this approach be available?"
- options:
  - "All my projects" - Install to ~/.claude/gsd-extensions/ (Recommended)
  - "This project only" - Install to .planning/extensions/
</step>

<step name="generate_components">
Create all components with proper cross-references.

**Naming convention:** All components share a prefix (e.g., `spike-*` for spike-first approach).

**1. Create directories:**

```bash
if [[ "$SCOPE" == "global" ]]; then
  BASE="$HOME/.claude/gsd-extensions"
else
  BASE=".planning/extensions"
fi

mkdir -p "$BASE/workflows"
mkdir -p "$BASE/references"  # if needed
mkdir -p "$BASE/agents"      # if needed
mkdir -p "$BASE/templates"   # if needed
```

**2. Generate workflow:**

The workflow is the orchestrator. It must:
- Reference any supporting components via @-paths
- Define when agents are spawned
- Specify which templates to use for output

Use the structure from workflow-structure.md.

**3. Generate reference (if needed):**

Populate with actual domain knowledge gathered from conversation.
Include patterns, anti-patterns, and quick reference.

Use the structure from reference-structure.md.

**4. Generate agent (if needed):**

Define role, expertise, execution flow, and output format.
Grant minimum necessary tools.

Use the structure from agent-structure.md.

**5. Generate template (if needed):**

Include template body, guidelines, and examples.
Document all placeholders.

Use the structure from template-structure.md.

**Wire components together:**

In the workflow:
```xml
<required_reading>
@{BASE}/references/{name}-patterns.md
</required_reading>

<step name="spawn_agent">
Task(
  prompt="@{BASE}/agents/{name}-agent.md

  <context>...</context>",
  subagent_type="general-purpose",
  model="sonnet"
)
</step>

<output>
Use template: @{BASE}/templates/{name}-template.md
</output>
```
</step>

<step name="validate_all">
Validate each component:

```bash
for file in "$BASE"/*/"${PREFIX}-"*.md; do
  echo "Validating: $file"
  # Check YAML frontmatter
  head -20 "$file" | grep -E "^(name|description):"
  # Check XML balance
  OPEN=$(grep -oE '<[a-z_]+[^/>]*>' "$file" | wc -l)
  CLOSE=$(grep -oE '</[a-z_]+>' "$file" | wc -l)
  [[ "$OPEN" -eq "$CLOSE" ]] && echo "  ✓ XML balanced" || echo "  ✗ XML unbalanced"
done
```

Check cross-references resolve:
```bash
grep -oE '@[~./][^[:space:]]+' "$BASE/workflows/${PREFIX}-"*.md | while read ref; do
  path="${ref#@}"
  path="${path/#\~/$HOME}"
  [[ -f "$path" ]] && echo "  ✓ $ref" || echo "  ✗ $ref NOT FOUND"
done
```
</step>

<step name="provide_usage">
Show the user how to use their new approach:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 GSD ► APPROACH CREATED: {name}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Components

| Type | File | Purpose |
|------|------|---------|
| Workflow | {path} | {purpose} |
| Reference | {path} | {purpose} |
| Agent | {path} | {purpose} |
| Template | {path} | {purpose} |

## How to Use

{If replaces built-in:}
Your approach automatically activates when you run `{trigger command}`.
GSD will use your workflow instead of the built-in.

{If new capability:}
Reference the workflow in your commands or other workflows:
@{workflow_path}

{If has custom trigger:}
Add to your PLAN.md or invoke directly:
@{workflow_path}

## To Customize Later

Edit the files directly at:
{BASE}/{type}/{name}.md

## To Remove

/gsd:extend remove {name}

───────────────────────────────────────────────────────────────
```
</step>

</process>

<success_criteria>
- [ ] User's approach fully understood through conversation
- [ ] All needed components identified
- [ ] Scope determined (project vs global)
- [ ] All components generated with correct structure
- [ ] Components properly cross-referenced
- [ ] All components pass validation
- [ ] User knows how to use the approach
</success_criteria>
