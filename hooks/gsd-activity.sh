#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# GSD Activity Hook
# ═══════════════════════════════════════════════════════════════════════════════
#
# PostToolUse hook that reports real-time activity during autopilot execution.
# Writes structured messages to a named pipe that autopilot.sh reads.
#
# Only active when GSD_AUTOPILOT=1 (set by autopilot.sh)
#
# Message format:
#   STAGE:<subagent_type>:<description>
#   FILE:<operation>:<filepath>
#   COMMIT:<message>
#   TASK:<plan>:<task_num>:<task_name>
#
# ═══════════════════════════════════════════════════════════════════════════════

# Exit silently if not in autopilot mode
[ "$GSD_AUTOPILOT" != "1" ] && exit 0

# Exit if no pipe configured
[ -z "$GSD_ACTIVITY_PIPE" ] && exit 0

# Exit if pipe doesn't exist
[ ! -p "$GSD_ACTIVITY_PIPE" ] && exit 0

# Read hook data from stdin
HOOK_DATA=$(cat)

# Extract tool info
TOOL=$(echo "$HOOK_DATA" | jq -r '.tool_name // empty' 2>/dev/null)
INPUT=$(echo "$HOOK_DATA" | jq -r '.tool_input // empty' 2>/dev/null)

# Exit if we couldn't parse
[ -z "$TOOL" ] && exit 0

# Get project directory for path stripping
PROJECT_DIR="${GSD_PROJECT_DIR:-$(pwd)}"

# ─────────────────────────────────────────────────────────────────────────────
# Helper: Write to pipe (non-blocking)
# ─────────────────────────────────────────────────────────────────────────────
write_activity() {
  # Non-blocking write - if pipe is full, skip rather than hang
  echo "$1" > "$GSD_ACTIVITY_PIPE" 2>/dev/null &
  local pid=$!

  # Give it a moment, then kill if stuck
  sleep 0.1
  kill $pid 2>/dev/null
  wait $pid 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# Helper: Strip project path from filepath
# ─────────────────────────────────────────────────────────────────────────────
strip_path() {
  echo "$1" | sed "s|^$PROJECT_DIR/||" | sed "s|^$HOME|~|"
}

# ─────────────────────────────────────────────────────────────────────────────
# Process by tool type
# ─────────────────────────────────────────────────────────────────────────────

case "$TOOL" in

  # ─────────────────────────────────────────────────────────────────────────
  # Task tool - subagent spawned
  # ─────────────────────────────────────────────────────────────────────────
  Task)
    TYPE=$(echo "$INPUT" | jq -r '.subagent_type // "unknown"' 2>/dev/null)
    DESC=$(echo "$INPUT" | jq -r '.description // ""' 2>/dev/null)

    # Only report GSD subagents
    case "$TYPE" in
      gsd-phase-researcher|gsd-planner|gsd-plan-checker|gsd-executor|gsd-verifier|gsd-integration-checker)
        write_activity "STAGE:$TYPE:$DESC"
        ;;
    esac
    ;;

  # ─────────────────────────────────────────────────────────────────────────
  # Write tool - file created
  # ─────────────────────────────────────────────────────────────────────────
  Write)
    FILE=$(echo "$INPUT" | jq -r '.file_path // ""' 2>/dev/null)
    [ -n "$FILE" ] && write_activity "FILE:write:$(strip_path "$FILE")"
    ;;

  # ─────────────────────────────────────────────────────────────────────────
  # Edit tool - file modified
  # ─────────────────────────────────────────────────────────────────────────
  Edit)
    FILE=$(echo "$INPUT" | jq -r '.file_path // ""' 2>/dev/null)
    [ -n "$FILE" ] && write_activity "FILE:edit:$(strip_path "$FILE")"
    ;;

  # ─────────────────────────────────────────────────────────────────────────
  # Read tool - file read (only report source files, not planning docs)
  # ─────────────────────────────────────────────────────────────────────────
  Read)
    FILE=$(echo "$INPUT" | jq -r '.file_path // ""' 2>/dev/null)

    # Skip planning docs and common noise
    case "$FILE" in
      *.planning/*|*/.claude/*|*/node_modules/*|*/.git/*)
        # Skip these
        ;;
      *)
        [ -n "$FILE" ] && write_activity "FILE:read:$(strip_path "$FILE")"
        ;;
    esac
    ;;

  # ─────────────────────────────────────────────────────────────────────────
  # Bash tool - check for git commits
  # ─────────────────────────────────────────────────────────────────────────
  Bash)
    CMD=$(echo "$INPUT" | jq -r '.command // ""' 2>/dev/null)

    # Detect git commits
    if echo "$CMD" | grep -q "git commit"; then
      # Extract commit message - try multiple patterns
      MSG=$(echo "$CMD" | grep -oP '(?<=-m ")[^"]+' 2>/dev/null | head -1)
      [ -z "$MSG" ] && MSG=$(echo "$CMD" | grep -oP "(?<=-m ')[^']+" 2>/dev/null | head -1)
      [ -z "$MSG" ] && MSG=$(echo "$CMD" | grep -oP '(?<=-m )[^ ]+' 2>/dev/null | head -1)

      [ -n "$MSG" ] && write_activity "COMMIT:$MSG"
    fi

    # Detect test runs
    if echo "$CMD" | grep -qE "(npm test|yarn test|pytest|go test|cargo test)"; then
      write_activity "TEST:running"
    fi
    ;;

  # ─────────────────────────────────────────────────────────────────────────
  # TodoWrite - task progress indicator
  # ─────────────────────────────────────────────────────────────────────────
  TodoWrite)
    # Extract in_progress task
    TODOS=$(echo "$INPUT" | jq -r '.todos // []' 2>/dev/null)
    CURRENT=$(echo "$TODOS" | jq -r '.[] | select(.status == "in_progress") | .content' 2>/dev/null | head -1)

    [ -n "$CURRENT" ] && write_activity "TODO:$CURRENT"
    ;;

esac

exit 0
