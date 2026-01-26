<agent_structure>

## Agent Extensions

Agents are specialized subagents spawned during GSD operations. They have specific expertise, limited tool access, and focused responsibilities.

## Required Frontmatter

```yaml
---
name: agent-name
description: What this agent does and when to spawn it
tools: [Read, Write, Edit, Bash, Grep, Glob, WebFetch, WebSearch]
color: green  # Terminal output color
spawn_from:
  - plan-phase           # Spawnable from planning
  - execute-plan         # Spawnable during execution
  - execute-phase        # Spawnable from orchestrator
  - verify-phase         # Spawnable during verification
  - custom               # Spawnable via explicit Task call
---
```

## Available Tools

Choose tools based on agent responsibility:

| Tool | Use For |
|------|---------|
| Read | Reading files for context |
| Write | Creating new files |
| Edit | Modifying existing files |
| Bash | Running commands |
| Grep | Searching file contents |
| Glob | Finding files by pattern |
| WebFetch | Fetching web content |
| WebSearch | Searching the web |
| mcp__context7__* | Library documentation lookup |

**Principle:** Grant minimum tools needed. More tools = more context usage = lower quality.

## Agent Body Structure

```xml
<role>
You are a [specific role]. You [do what] when [triggered how].

Your job: [primary responsibility]
</role>

<expertise>
Domain knowledge relevant to this agent's specialty.

- Key concept 1
- Key concept 2
- Key concept 3
</expertise>

<execution_flow>

<step name="understand_context">
Load and parse input context provided by spawner.
</step>

<step name="perform_task">
Core task execution.
</step>

<step name="produce_output">
Generate expected output format.
</step>

</execution_flow>

<output_format>
Structured format for agent's return value.

## {SECTION_NAME}

**Field:** value
**Field:** value

### Details

{content}
</output_format>

<success_criteria>
- [ ] Criterion one
- [ ] Criterion two
</success_criteria>
```

## Spawning Agents

Agents are spawned via the Task tool:

```
Task(
  prompt="<context>...</context>

  Execute as agent: @~/.claude/gsd-extensions/agents/my-agent.md",
  subagent_type="gsd-executor",  # or other base type
  model="sonnet",
  description="Brief description"
)
```

**Important:** The `subagent_type` must be a registered type. Custom agents typically use an existing base type with additional instructions from the agent file.

## Agent Communication Pattern

Agents receive context from spawner:

```xml
<context>
**Project:** @.planning/PROJECT.md
**Phase:** {phase_number}
**Specific input:** {data from spawner}
</context>
```

Agents return structured results:

```markdown
## AGENT_COMPLETE

**Status:** success | partial | blocked
**Summary:** One-line result

### Output

{Structured output based on agent's output_format}

### Issues (if any)

- Issue 1
- Issue 2
```

## Example: Security Auditor Agent

```yaml
---
name: security-auditor
description: Reviews code for security vulnerabilities during execution
tools: [Read, Grep, Glob]
color: red
spawn_from: [execute-plan, verify-phase]
---
```

```xml
<role>
You are a security auditor. You review code changes for security vulnerabilities
before they're committed.

Your job: Identify security issues in new or modified code, categorize by
severity, and provide actionable remediation guidance.
</role>

<expertise>
## Security Review Domains

**Injection vulnerabilities:**
- SQL injection (parameterize queries)
- Command injection (validate/escape inputs)
- XSS (sanitize output, use CSP)

**Authentication/Authorization:**
- Insecure credential storage (use proper hashing)
- Missing authorization checks
- Session management issues

**Data exposure:**
- Sensitive data in logs
- Hardcoded secrets
- Overly permissive CORS

**Dependencies:**
- Known vulnerable packages
- Outdated dependencies
</expertise>

<execution_flow>

<step name="identify_changes">
Identify files modified in current task:

```bash
git diff --name-only HEAD~1
```

Filter for code files (.ts, .js, .py, etc.)
</step>

<step name="review_patterns">
For each file, search for security anti-patterns:

```bash
# Hardcoded secrets
grep -n "password\|secret\|api_key\|token" $FILE

# SQL construction
grep -n "query.*\+" $FILE

# Dangerous functions
grep -n "eval\|exec\|innerHTML" $FILE
```
</step>

<step name="categorize_findings">
For each finding:
1. Verify it's actually a vulnerability (not false positive)
2. Assign severity: critical, high, medium, low
3. Provide remediation guidance
</step>

<step name="generate_report">
Produce security review report.
</step>

</execution_flow>

<output_format>
## SECURITY_REVIEW

**Files reviewed:** {count}
**Issues found:** {count by severity}

### Critical Issues

| File | Line | Issue | Remediation |
|------|------|-------|-------------|
| path | N | description | fix |

### High Issues

...

### Recommendations

1. Recommendation
2. Recommendation

### Approved

{yes/no - yes if no critical/high issues}
</output_format>

<success_criteria>
- [ ] All modified files reviewed
- [ ] Issues categorized by severity
- [ ] Remediation guidance provided
- [ ] Clear approve/reject decision
</success_criteria>
```

## Agent Best Practices

**1. Single responsibility**
Each agent does one thing well. Don't combine security review with performance analysis.

**2. Minimal tools**
Grant only tools the agent needs. Security auditor doesn't need Write or WebSearch.

**3. Structured output**
Always use consistent output format. Spawner needs to parse results.

**4. Fail gracefully**
If agent can't complete, return partial results with clear status.

**5. Be specific in role**
Generic "helper" agents are useless. Specific expertise is valuable.

## Registering Custom Agents

For GSD to recognize custom agents as valid `subagent_type` values, they need to be registered in `~/.claude/settings.json`:

```json
{
  "customAgents": [
    {
      "name": "security-auditor",
      "path": "~/.claude/gsd-extensions/agents/security-auditor.md"
    }
  ]
}
```

Alternatively, use existing `subagent_type` (like `general-purpose`) and load agent instructions via @-reference:

```
Task(
  prompt="@~/.claude/gsd-extensions/agents/security-auditor.md

  Review: {files}",
  subagent_type="general-purpose",
  model="sonnet"
)
```

This is the recommended approach for custom agents.

</agent_structure>
