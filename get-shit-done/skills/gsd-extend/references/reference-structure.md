<reference_structure>

## Reference Extensions

References are domain knowledge files loaded during GSD operations. They provide context, patterns, best practices, and project-specific conventions.

## Required Frontmatter

```yaml
---
name: reference-name
description: What knowledge this provides
load_when:
  - keyword1         # Load when phase/plan mentions this
  - keyword2         # Multiple keywords supported
  - always           # Load for every operation
auto_load_for:
  - plan-phase       # Auto-load during planning
  - execute-plan     # Auto-load during execution
  - verify-phase     # Auto-load during verification
---
```

## Reference Body Structure

```xml
<{reference_topic}>

## Overview

High-level summary of this knowledge domain.

## Core Concepts

### Concept 1

Explanation of first concept.

**Key points:**
- Point one
- Point two

**Example:**
```code
example here
```

### Concept 2

Explanation of second concept.

## Patterns

### Pattern Name

**When to use:** Conditions for this pattern

**Implementation:**
```code
pattern implementation
```

**Avoid:** Common mistakes

## Anti-Patterns

### Anti-Pattern Name

**Problem:** What goes wrong

**Why it happens:** Root cause

**Better approach:** What to do instead

## Quick Reference

| Term | Definition |
|------|------------|
| term1 | definition |
| term2 | definition |

</{reference_topic}>
```

## Load Triggers

References load based on context matching:

**Keyword matching:**
```yaml
load_when:
  - authentication
  - auth
  - login
  - jwt
```

When any planning/execution content mentions these keywords, reference is loaded.

**Phase name matching:**
```yaml
load_when:
  - "*-auth-*"      # Any phase with "auth" in name
  - "01-*"          # First phase only
```

**Always load:**
```yaml
load_when:
  - always
```

Use sparingly - adds to every context.

## Auto-loading

References can auto-load for specific operations:

```yaml
auto_load_for:
  - plan-phase     # Loaded when planning any phase
  - execute-plan   # Loaded when executing any plan
```

This is independent of keyword matching.

## Example: React Patterns Reference

```yaml
---
name: react-patterns
description: React 19 patterns and conventions for this project
load_when:
  - react
  - component
  - hook
  - tsx
  - jsx
  - frontend
  - ui
auto_load_for: []
---
```

```xml
<react_patterns>

## Overview

This project uses React 19 with Server Components as default.
All components are server components unless marked with 'use client'.

## Component Conventions

### File Naming

- Components: `PascalCase.tsx` (e.g., `UserProfile.tsx`)
- Hooks: `useCamelCase.ts` (e.g., `useAuth.ts`)
- Utils: `camelCase.ts` (e.g., `formatDate.ts`)

### Component Structure

```tsx
// components/UserProfile.tsx

interface UserProfileProps {
  userId: string;
  showEmail?: boolean;
}

export function UserProfile({ userId, showEmail = false }: UserProfileProps) {
  // Implementation
}
```

**Rules:**
- Named exports (not default)
- Props interface above component
- Destructure props in signature
- Optional props have defaults

### Client Components

```tsx
'use client';

import { useState } from 'react';

export function Counter() {
  const [count, setCount] = useState(0);
  // ...
}
```

Mark as client component when:
- Using useState, useEffect, useReducer
- Using browser APIs (localStorage, window)
- Using event handlers (onClick, onChange)
- Using third-party client libraries

## Data Fetching

### Server Components (preferred)

```tsx
// Fetches at request time
async function UserList() {
  const users = await db.user.findMany();
  return <ul>{users.map(u => <li key={u.id}>{u.name}</li>)}</ul>;
}
```

### Client Components (when needed)

```tsx
'use client';

import useSWR from 'swr';

function UserList() {
  const { data: users } = useSWR('/api/users', fetcher);
  // ...
}
```

## State Management

### Local State

Use `useState` for component-local state.

### Shared State

Use React Context for:
- Theme/appearance preferences
- User session
- Feature flags

Do NOT use Context for:
- Server data (use SWR/React Query)
- Form state (use react-hook-form)

## Forms

```tsx
'use client';

import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';

const schema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
});

function LoginForm() {
  const { register, handleSubmit, formState } = useForm({
    resolver: zodResolver(schema),
  });
  // ...
}
```

## Anti-Patterns

### Prop Drilling

**Bad:**
```tsx
<App user={user}>
  <Layout user={user}>
    <Sidebar user={user}>
      <UserInfo user={user} />
```

**Good:** Use Context or component composition.

### useEffect for Data Fetching

**Bad:**
```tsx
useEffect(() => {
  fetch('/api/users').then(setUsers);
}, []);
```

**Good:** Use server components or SWR.

### Inline Object Creation

**Bad:**
```tsx
<Component style={{ color: 'red' }} />
```

**Good:**
```tsx
const styles = { color: 'red' };
<Component style={styles} />
```

## Quick Reference

| Pattern | Use For |
|---------|---------|
| Server Component | Data fetching, static content |
| Client Component | Interactivity, browser APIs |
| Context | Theme, auth, app-wide settings |
| SWR | Client-side data fetching |
| react-hook-form | Complex forms |
| Suspense | Loading states |

</react_patterns>
```

## Example: Project Conventions Reference

```yaml
---
name: project-conventions
description: Project-specific coding conventions
load_when:
  - always
auto_load_for:
  - plan-phase
  - execute-plan
---
```

```xml
<project_conventions>

## Overview

Conventions specific to this project. These override general best practices
where they conflict.

## API Endpoints

All API routes follow pattern:
```
/api/{resource}/{action}

GET    /api/users          # List
GET    /api/users/:id      # Get one
POST   /api/users          # Create
PATCH  /api/users/:id      # Update
DELETE /api/users/:id      # Delete
```

## Error Handling

API errors return:
```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Human readable message",
    "details": {}
  }
}
```

## Database

- All tables have `id` (UUID), `created_at`, `updated_at`
- Soft delete via `deleted_at` timestamp
- Use Prisma for all database access

## Testing

- Unit tests: `*.test.ts` co-located with source
- Integration tests: `tests/integration/`
- E2E tests: `tests/e2e/`

Run with `npm test` (unit) or `npm run test:e2e` (e2e)

## Git

- Branch naming: `feature/description`, `fix/description`
- Commits: Conventional commits format
- PRs: Require at least description and test plan

</project_conventions>
```

## Reference Best Practices

**1. Be specific**
Generic knowledge is less useful. Include project-specific details.

**2. Include examples**
Code examples are worth 1000 words of explanation.

**3. Document anti-patterns**
Knowing what NOT to do is as valuable as knowing what to do.

**4. Keep updated**
References reflect current state. Update when patterns change.

**5. Use appropriate load triggers**
Too many triggers = loaded when not relevant.
Too few triggers = not loaded when needed.

**6. Avoid duplication**
Don't repeat built-in GSD references. Extend or override them.

</reference_structure>
