---
name: gsd:extend
description: Create custom GSD approaches - workflows, agents, references, templates
argument-hint: "[list | create | remove <name>]"
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
---

<objective>

Create and manage custom GSD approaches. An approach is a complete methodology - a workflow with supporting references, agents, and templates that work together.

**Examples of approaches:**
- Spike-first planning (explore before formalizing)
- Security-focused execution (audit before each commit)
- API-first development (OpenAPI spec drives implementation)
- TDD-strict (enforce red-green-refactor cycle)

</objective>

<execution_context>

@~/.claude/get-shit-done/skills/gsd-extend/SKILL.md

</execution_context>

<context>

**Arguments:** $ARGUMENTS

**Extension locations:**
- Project: `.planning/extensions/`
- Global: `~/.claude/gsd-extensions/`

</context>

<process>

## Parse Arguments

**If `$ARGUMENTS` is empty or "create":**
→ Load `workflows/create-approach.md`
→ Start conversational discovery

**If `$ARGUMENTS` is "list":**
→ Load `workflows/list-extensions.md`
→ Show all installed extensions

**If `$ARGUMENTS` starts with "remove":**
→ Load `workflows/remove-extension.md`
→ Parse the name and remove

**If ambiguous:**
Use AskUserQuestion:
- header: "Action"
- question: "What would you like to do?"
- options:
  - "Create an approach" - Build a custom methodology through conversation
  - "List extensions" - See what's installed
  - "Remove an extension" - Delete something

## Execute

Follow the loaded workflow completely.

</process>

<success_criteria>

- [ ] User intent understood
- [ ] Correct workflow loaded
- [ ] Workflow executed successfully
- [ ] User knows next steps

</success_criteria>
