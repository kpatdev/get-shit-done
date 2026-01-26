---
name: reference-template
description: Template for creating custom reference extensions
used_by:
  - create-reference
placeholders:
  - name
  - description
  - load_when
  - auto_load_for
  - topic
  - overview
  - core_concepts
  - patterns
  - anti_patterns
  - quick_reference
---

<template>

```yaml
---
name: {name}
description: {description}
load_when:
  - {keywords}
auto_load_for:
  - {operations}
---
```

```xml
<{topic}>

## Overview

{overview}

## Core Concepts

{core_concepts}

## Patterns

{patterns}

## Anti-Patterns

{anti_patterns}

## Quick Reference

{quick_reference}

</{topic}>
```

</template>

<guidelines>

## How to Fill This Template

**{name}:** kebab-case identifier (e.g., `react-patterns`, `stripe-integration`)

**{description}:** One sentence describing what knowledge this provides

**{load_when}:** Array of keywords that trigger loading:
- Technology names: `react`, `prisma`, `stripe`
- Concepts: `authentication`, `payments`, `api`
- File patterns: `*.tsx`, `route.ts`
- `always` for universal loading (use sparingly)

**{auto_load_for}:** Array of operations to auto-load for:
- `plan-phase` - Load during planning
- `execute-plan` - Load during execution
- `verify-phase` - Load during verification
- `[]` for no auto-loading

**{topic}:** XML tag name matching the knowledge domain (e.g., `react_patterns`)

**{overview}:** 2-3 sentences summarizing this knowledge area

**{core_concepts}:** Key concepts explained with:
- Subsections for each concept
- Key points as bullets
- Code examples where helpful

**{patterns}:** Recommended approaches with:
- When to use each pattern
- Implementation examples
- Common mistakes to avoid

**{anti_patterns}:** What NOT to do with:
- Problem description
- Why it happens
- Better approach

**{quick_reference}:** Cheat sheet table of terms and definitions

</guidelines>

<examples>

## Good Example

```yaml
---
name: prisma-patterns
description: Prisma ORM patterns and best practices for this project
load_when:
  - prisma
  - database
  - schema
  - model
  - db
auto_load_for: []
---
```

```xml
<prisma_patterns>

## Overview

This project uses Prisma as the ORM. All database access goes through Prisma
Client. Schema is in `prisma/schema.prisma`.

## Core Concepts

### Schema Organization

Models are grouped by domain in schema.prisma:
- User and auth models together
- Content models together
- System/config models at the end

**Naming:**
- Models: PascalCase singular (User, not Users)
- Fields: camelCase
- Relations: named descriptively (author, posts)

### Migrations

```bash
# Development: push without migration
npx prisma db push

# Production: create migration
npx prisma migrate dev --name description
```

## Patterns

### Eager Loading

**When to use:** Need related data in same request

```typescript
const user = await prisma.user.findUnique({
  where: { id },
  include: {
    posts: true,
    profile: true,
  },
});
```

### Transaction

**When to use:** Multiple writes that must succeed together

```typescript
await prisma.$transaction([
  prisma.user.update({ ... }),
  prisma.audit.create({ ... }),
]);
```

## Anti-Patterns

### N+1 Queries

**Problem:** Fetching related data in a loop

```typescript
// BAD
const users = await prisma.user.findMany();
for (const user of users) {
  const posts = await prisma.post.findMany({ where: { authorId: user.id } });
}
```

**Better:**
```typescript
const users = await prisma.user.findMany({
  include: { posts: true },
});
```

### Raw Queries for Simple Operations

**Problem:** Using $queryRaw when Prisma methods work

**Better:** Use Prisma Client methods. They're type-safe and handle escaping.

## Quick Reference

| Operation | Method |
|-----------|--------|
| Find one | `findUnique`, `findFirst` |
| Find many | `findMany` |
| Create | `create`, `createMany` |
| Update | `update`, `updateMany` |
| Delete | `delete`, `deleteMany` |
| Count | `count` |

</prisma_patterns>
```

## Bad Example

```yaml
---
name: database
description: Database stuff
load_when:
  - always
---
```

Problems:
- Name too generic
- Description vague
- `always` load is wasteful
- No actual content
- No patterns or examples

</examples>
