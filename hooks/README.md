# GSD Hooks

Hooks that enable real-time activity reporting during autopilot execution.

## Installation

The GSD installer automatically copies hooks to `~/.claude/hooks/` and configures them in your Claude Code settings.

If you need to manually configure, add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": {
          "tool_name": ["Task", "Write", "Edit", "Read", "Bash", "TodoWrite"]
        },
        "command": "bash ~/.claude/hooks/gsd-activity.sh"
      }
    ]
  }
}
```

## How It Works

### Environment Variables

The autopilot script sets these variables that hooks check:

| Variable | Purpose |
|----------|---------|
| `GSD_AUTOPILOT` | Set to `1` when running in autopilot mode |
| `GSD_ACTIVITY_PIPE` | Path to named pipe for IPC |
| `GSD_PROJECT_DIR` | Project root directory |
| `GSD_LOG_DIR` | Log directory path |

### Message Protocol

Hooks write structured messages to the activity pipe:

| Message | Format | Trigger |
|---------|--------|---------|
| Stage change | `STAGE:<subagent_type>:<description>` | Task tool with GSD subagent |
| File activity | `FILE:<op>:<filepath>` | Write, Edit, Read tools |
| Git commit | `COMMIT:<message>` | Bash with git commit |
| Test run | `TEST:running` | Bash with test commands |
| Task update | `TODO:<task_name>` | TodoWrite with in_progress task |

### Stage Mapping

| Subagent Type | Display Name |
|---------------|--------------|
| `gsd-phase-researcher` | RESEARCH |
| `gsd-planner` | PLANNING |
| `gsd-plan-checker` | CHECKING |
| `gsd-executor` | BUILDING |
| `gsd-verifier` | VERIFYING |
| `gsd-integration-checker` | INTEGRATING |

## Autopilot-Only Activation

Hooks are no-op outside autopilot mode. The first line of `gsd-activity.sh` checks:

```bash
[ "$GSD_AUTOPILOT" != "1" ] && exit 0
```

This ensures hooks don't interfere with normal Claude Code usage.

## Display Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  autopilot.sh                                                   │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │  claude -p "/gsd:plan-phase 3"                            │ │
│  │                                                            │ │
│  │  ┌──────────────────────────────────────────────────────┐ │ │
│  │  │  Hook: PostToolUse                                   │ │ │
│  │  │  → writes STAGE:gsd-phase-researcher:...             │───┼──→ activity.pipe
│  │  └──────────────────────────────────────────────────────┘ │ │         │
│  │                                                            │ │         │
│  │  ┌──────────────────────────────────────────────────────┐ │ │         │
│  │  │  Hook: PostToolUse (Write)                           │ │ │         │
│  │  │  → writes FILE:write:src/auth.ts                     │───┼─────────┤
│  │  └──────────────────────────────────────────────────────┘ │ │         │
│  └───────────────────────────────────────────────────────────┘ │         │
│                                                                 │         ▼
│  ┌───────────────────────────────────────────────────────────┐ │  ┌─────────────┐
│  │  Background reader process                                │◄┼──│ Named pipe  │
│  │  → updates display state files                            │ │  └─────────────┘
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │  Display refresh process (0.5s interval)                  │ │
│  │  → reads state files, redraws terminal                    │ │
│  └───────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Debugging

If hooks aren't working:

1. Check autopilot is setting environment variables:
   ```bash
   echo $GSD_AUTOPILOT
   echo $GSD_ACTIVITY_PIPE
   ```

2. Check pipe exists:
   ```bash
   ls -la .planning/logs/activity.pipe
   ```

3. Check hook is executable:
   ```bash
   ls -la ~/.claude/hooks/gsd-activity.sh
   ```

4. Test hook manually:
   ```bash
   echo '{"tool_name": "Task", "tool_input": {"subagent_type": "gsd-executor", "description": "test"}}' | bash ~/.claude/hooks/gsd-activity.sh
   ```
