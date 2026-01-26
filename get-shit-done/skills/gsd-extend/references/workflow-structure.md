<workflow_structure>

## Workflow Extensions

Workflows define execution patterns - sequences of steps that GSD follows to accomplish tasks like planning, execution, or verification.

## Required Frontmatter

```yaml
---
name: workflow-name
description: What this workflow accomplishes
triggers:
  - plan-phase          # Triggered by /gsd:plan-phase
  - execute-plan        # Triggered during plan execution
  - execute-phase       # Triggered by /gsd:execute-phase
  - verify-phase        # Triggered by verification
  - custom              # Custom trigger (called explicitly)
replaces: built-in-name  # Optional: replace a built-in workflow
requires: [reference-names]  # Optional: auto-load these references
---
```

## Workflow Body Structure

```xml
<purpose>
What this workflow accomplishes.
</purpose>

<when_to_use>
Conditions that trigger this workflow.
</when_to_use>

<required_reading>
@~/.claude/get-shit-done/references/some-reference.md
@.planning/extensions/references/custom-reference.md
</required_reading>

<process>

<step name="step_one" priority="first">
First step description.

Code examples:
```bash
command --here
```

Conditional logic:
<if condition="some condition">
What to do when condition is true.
</if>
</step>

<step name="step_two">
Second step description.
</step>

<step name="step_three">
Third step description.
</step>

</process>

<success_criteria>
- [ ] Criterion one
- [ ] Criterion two
- [ ] Criterion three
</success_criteria>
```

## Step Attributes

| Attribute | Values | Purpose |
|-----------|--------|---------|
| `name` | snake_case | Identifier for the step |
| `priority` | first, second, last | Execution order hints |
| `conditional` | if/when expression | Only run if condition met |
| `parallel` | true/false | Can run with other parallel steps |

## Conditional Logic

Workflows can include conditional sections:

```xml
<if mode="yolo">
Auto-approve behavior
</if>

<if mode="interactive">
Confirmation-required behavior
</if>

<if exists=".planning/DISCOVERY.md">
Behavior when discovery exists
</if>

<if config="workflow.research">
Behavior when research is enabled in config
</if>
```

## Context Loading

Workflows specify what context to load:

```xml
<required_reading>
@~/.claude/get-shit-done/references/deviation-rules.md
</required_reading>

<conditional_loading>
**If plan has checkpoints:**
@~/.claude/get-shit-done/workflows/execute-plan-checkpoints.md

**If authentication error:**
@~/.claude/get-shit-done/workflows/execute-plan-auth.md
</conditional_loading>
```

## Output Specification

Workflows should specify expected outputs:

```xml
<output>
After completion, create:
- `.planning/phases/XX-name/{phase}-{plan}-SUMMARY.md`

Use template:
@~/.claude/get-shit-done/templates/summary.md
</output>
```

## Integration with GSD Commands

To use a custom workflow from a GSD command:

**Option 1: Replace built-in**
Name your workflow same as built-in (e.g., `execute-plan.md`). GSD automatically uses yours.

**Option 2: Explicit reference**
In your command or another workflow:
```xml
<execution_context>
@.planning/extensions/workflows/my-workflow.md
</execution_context>
```

**Option 3: Spawn pattern**
If workflow runs as subagent:
```
Task(prompt="Follow workflow: @~/.claude/gsd-extensions/workflows/my-workflow.md", ...)
```

## Example: Custom Planning Workflow

```yaml
---
name: spike-first-planning
description: Plan by spiking first, then formalizing
triggers: [plan-phase]
replaces: null  # Alternative to default, not replacement
---
```

```xml
<purpose>
Alternative planning workflow that creates a spike implementation first,
then derives formal plans from what worked.
</purpose>

<when_to_use>
- Domain is unfamiliar
- Requirements are fuzzy
- You want to discover approach through doing
</when_to_use>

<process>

<step name="create_spike_plan">
Create a minimal spike plan:
- Single task: "Spike: {phase goal}"
- No formal structure
- Goal is learning, not delivery
</step>

<step name="execute_spike">
Execute the spike:
- Time-boxed (1-2 hours)
- Document discoveries
- Note what worked and what didn't
</step>

<step name="derive_formal_plans">
From spike learnings:
- Extract the approach that worked
- Formalize into proper PLAN.md files
- Add verification and success criteria
</step>

<step name="cleanup_spike">
- Archive spike artifacts
- Proceed with formal execution
</step>

</process>

<success_criteria>
- [ ] Spike completed and learnings documented
- [ ] Formal plans derived from spike
- [ ] Ready for normal execution
</success_criteria>
```

## Common Workflow Patterns

**Sequential execution:**
```xml
<step name="a">...</step>
<step name="b">Depends on step a results...</step>
<step name="c">Depends on step b results...</step>
```

**Parallel steps:**
```xml
<step name="research_a" parallel="true">...</step>
<step name="research_b" parallel="true">...</step>
<step name="synthesize">Combines a and b...</step>
```

**Loop pattern:**
```xml
<step name="iterate">
For each {item}:
1. Process item
2. Check result
3. Continue or break

Loop until condition met.
</step>
```

**Decision gate:**
```xml
<step name="decision_gate">
Present options via AskUserQuestion.
Route to appropriate next step based on choice.
</step>
```

</workflow_structure>
