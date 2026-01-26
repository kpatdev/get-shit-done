---
name: workflow-template
description: Template for creating custom workflow extensions
used_by:
  - create-workflow
placeholders:
  - name
  - description
  - triggers
  - replaces
  - requires
  - purpose
  - when_to_use
  - required_reading
  - steps
  - success_criteria
---

<template>

```yaml
---
name: {name}
description: {description}
triggers: [{triggers}]
replaces: {replaces}
requires: [{requires}]
---
```

```xml
<purpose>
{purpose}
</purpose>

<when_to_use>
{when_to_use}
</when_to_use>

<required_reading>
{required_reading}
</required_reading>

<process>

{steps}

</process>

<success_criteria>
{success_criteria}
</success_criteria>
```

</template>

<guidelines>

## How to Fill This Template

**{name}:** kebab-case identifier matching filename (e.g., `my-custom-workflow`)

**{description}:** One sentence describing what this workflow accomplishes

**{triggers}:** Array of trigger points:
- `plan-phase` - Triggered by /gsd:plan-phase
- `execute-plan` - Triggered during plan execution
- `execute-phase` - Triggered by /gsd:execute-phase
- `verify-phase` - Triggered during verification
- `custom` - Only triggered via explicit reference

**{replaces}:** Name of built-in workflow to override, or `null` for new capability

**{requires}:** Array of reference names this workflow needs, or `[]` for none

**{purpose}:** 2-3 sentences explaining what this workflow does and why

**{when_to_use}:** Bullet list of conditions that make this workflow appropriate

**{required_reading}:** @-references to files that must be loaded

**{steps}:** Series of `<step name="step_name">` elements, each containing:
- Clear description of what the step does
- Code examples if needed
- Conditional logic if needed

**{success_criteria}:** Markdown checklist of completion criteria

</guidelines>

<examples>

## Good Example

```yaml
---
name: spike-first-planning
description: Plan by creating a spike implementation first
triggers: [plan-phase]
replaces: null
requires: []
---
```

```xml
<purpose>
Alternative planning workflow that creates a spike implementation first,
then derives formal plans from what worked. Use when exploring unfamiliar
domains where requirements are fuzzy.
</purpose>

<when_to_use>
- Domain is unfamiliar and approach is uncertain
- Requirements are vague or evolving
- Learning through implementation is valuable
- Risk of over-planning is high
</when_to_use>

<process>

<step name="create_spike">
Create a time-boxed spike task focusing on the core uncertainty.
Goal is learning, not production quality.
</step>

<step name="execute_spike">
Execute spike with 1-2 hour time limit. Document:
- What worked
- What didn't work
- Key decisions made
- Approach to formalize
</step>

<step name="derive_plans">
From spike learnings, create formal PLAN.md files:
- Extract the successful approach
- Add proper verification
- Define success criteria
</step>

</process>

<success_criteria>
- [ ] Spike completed within time box
- [ ] Learnings documented
- [ ] Formal plans derived from spike
- [ ] Ready for normal execution
</success_criteria>
```

## Bad Example

```yaml
---
name: workflow
description: Does stuff
triggers: []
---
```

Problems:
- Name is too generic
- Description is vague
- No triggers defined
- No purpose section
- No steps documented
- No success criteria

</examples>
