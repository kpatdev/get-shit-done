#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# GSD Autopilot Script
# Generated: {{timestamp}}
# Project: {{project_name}}
# ═══════════════════════════════════════════════════════════════════════════════
#
# Autonomous execution of all remaining phases in the milestone.
# Each phase gets fresh 200k context via claude -p.
# State persists in .planning/ - safe to interrupt and resume.
#
# Features:
#   - Real-time activity display via hooks
#   - Stage tracking (research -> planning -> building -> verifying)
#   - Git safety checks (no uncommitted files left behind)
#   - Phase context display (what we're building and why)
#
# Usage:
#   bash .planning/autopilot.sh              # Run attached
#   nohup bash .planning/autopilot.sh &      # Run in background
#
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Signal to GSD commands that we're in autopilot mode
export GSD_AUTOPILOT=1

# ─────────────────────────────────────────────────────────────────────────────
# Configuration (filled by /gsd:autopilot)
# ─────────────────────────────────────────────────────────────────────────────

PROJECT_DIR="{{project_dir}}"
PROJECT_NAME="{{project_name}}"
PHASES=({{phases}})
CHECKPOINT_MODE="{{checkpoint_mode}}"
MAX_RETRIES={{max_retries}}
BUDGET_LIMIT={{budget_limit}}
WEBHOOK_URL="{{webhook_url}}"
MODEL_PROFILE="{{model_profile}}"

# ─────────────────────────────────────────────────────────────────────────────
# Derived paths
# ─────────────────────────────────────────────────────────────────────────────

LOG_DIR="$PROJECT_DIR/.planning/logs"
CHECKPOINT_DIR="$PROJECT_DIR/.planning/checkpoints"
STATE_FILE="$PROJECT_DIR/.planning/STATE.md"
ACTIVITY_PIPE="$PROJECT_DIR/.planning/logs/activity.pipe"

# Export for hooks
export GSD_ACTIVITY_PIPE="$ACTIVITY_PIPE"
export GSD_PROJECT_DIR="$PROJECT_DIR"
export GSD_LOG_DIR="$LOG_DIR"

# ─────────────────────────────────────────────────────────────────────────────
# Setup
# ─────────────────────────────────────────────────────────────────────────────

cd "$PROJECT_DIR"
mkdir -p "$LOG_DIR" "$CHECKPOINT_DIR/pending" "$CHECKPOINT_DIR/approved"

# Create activity pipe for hook communication
rm -f "$ACTIVITY_PIPE"
mkfifo "$ACTIVITY_PIPE" 2>/dev/null || true

# Lock directory (atomic creation prevents race condition)
LOCK_DIR="$PROJECT_DIR/.planning/autopilot.lock.d"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "ERROR: Autopilot already running (lock exists: $LOCK_DIR)"
  echo "If previous run crashed, remove manually: rmdir '$LOCK_DIR'"
  exit 1
fi

cleanup() {
  # Kill background processes
  [ -n "${READER_PID:-}" ] && kill $READER_PID 2>/dev/null
  [ -n "${DISPLAY_PID:-}" ] && kill $DISPLAY_PID 2>/dev/null

  # Remove lock and pipe
  rmdir "$LOCK_DIR" 2>/dev/null || true
  rm -f "$ACTIVITY_PIPE" 2>/dev/null || true

  # Restore cursor
  printf "\033[?25h" 2>/dev/null
}
trap cleanup EXIT INT TERM

# ─────────────────────────────────────────────────────────────────────────────
# Cross-platform helpers
# ─────────────────────────────────────────────────────────────────────────────

iso_timestamp() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

elapsed_since() {
  local start=$1
  local now=$(date +%s)
  local elapsed=$((now - start))
  local min=$((elapsed / 60))
  local sec=$((elapsed % 60))
  printf "%d:%02d" $min $sec
}

# ─────────────────────────────────────────────────────────────────────────────
# Terminal UI
# ─────────────────────────────────────────────────────────────────────────────

# Colors and formatting (auto-disabled if not a terminal)
if [ -t 1 ]; then
  C_RESET='\033[0m'
  C_BOLD='\033[1m'
  C_DIM='\033[2m'
  C_RED='\033[31m'
  C_GREEN='\033[32m'
  C_YELLOW='\033[33m'
  C_BLUE='\033[34m'
  C_CYAN='\033[36m'
  C_WHITE='\033[37m'
  CURSOR_HOME='\033[H'
  CURSOR_CLEAR='\033[J'
  CURSOR_LINE_CLEAR='\033[K'
  CURSOR_HIDE='\033[?25l'
  CURSOR_SHOW='\033[?25h'
else
  C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW=''
  C_BLUE='' C_CYAN='' C_WHITE=''
  CURSOR_HOME='' CURSOR_CLEAR='' CURSOR_LINE_CLEAR=''
  CURSOR_HIDE='' CURSOR_SHOW=''
fi

# ─────────────────────────────────────────────────────────────────────────────
# Display State (shared via temp files for subprocess communication)
# ─────────────────────────────────────────────────────────────────────────────

DISPLAY_STATE_DIR="$LOG_DIR/.display"
mkdir -p "$DISPLAY_STATE_DIR"

# Initialize display state files
echo "" > "$DISPLAY_STATE_DIR/current_stage"
echo "" > "$DISPLAY_STATE_DIR/stage_desc"
echo "0" > "$DISPLAY_STATE_DIR/stage_start"
echo "" > "$DISPLAY_STATE_DIR/completed_stages"
echo "" > "$DISPLAY_STATE_DIR/activity"

MAX_ACTIVITY_LINES=8

# ─────────────────────────────────────────────────────────────────────────────
# Stage Management
# ─────────────────────────────────────────────────────────────────────────────

stage_display_name() {
  local subagent_type="$1"
  case "$subagent_type" in
    gsd-phase-researcher)    echo "RESEARCH" ;;
    gsd-planner)             echo "PLANNING" ;;
    gsd-plan-checker)        echo "CHECKING" ;;
    gsd-executor)            echo "BUILDING" ;;
    gsd-verifier)            echo "VERIFYING" ;;
    gsd-integration-checker) echo "INTEGRATING" ;;
    *)                       echo "WORKING" ;;
  esac
}

set_stage() {
  local subagent_type="$1"
  local description="$2"

  # Complete previous stage if exists
  local prev_stage=$(cat "$DISPLAY_STATE_DIR/current_stage" 2>/dev/null)
  if [ -n "$prev_stage" ]; then
    local prev_start=$(cat "$DISPLAY_STATE_DIR/stage_start" 2>/dev/null)
    local elapsed=$(elapsed_since "$prev_start")
    echo "$prev_stage:$elapsed" >> "$DISPLAY_STATE_DIR/completed_stages"
  fi

  local stage_name=$(stage_display_name "$subagent_type")
  echo "$stage_name" > "$DISPLAY_STATE_DIR/current_stage"
  echo "$description" > "$DISPLAY_STATE_DIR/stage_desc"
  echo "$(date +%s)" > "$DISPLAY_STATE_DIR/stage_start"
}

complete_current_stage() {
  local curr_stage=$(cat "$DISPLAY_STATE_DIR/current_stage" 2>/dev/null)
  if [ -n "$curr_stage" ]; then
    local stage_start=$(cat "$DISPLAY_STATE_DIR/stage_start" 2>/dev/null)
    local elapsed=$(elapsed_since "$stage_start")
    echo "$curr_stage:$elapsed" >> "$DISPLAY_STATE_DIR/completed_stages"
    echo "" > "$DISPLAY_STATE_DIR/current_stage"
    echo "" > "$DISPLAY_STATE_DIR/stage_desc"
  fi
}

reset_stages() {
  echo "" > "$DISPLAY_STATE_DIR/current_stage"
  echo "" > "$DISPLAY_STATE_DIR/stage_desc"
  echo "0" > "$DISPLAY_STATE_DIR/stage_start"
  echo "" > "$DISPLAY_STATE_DIR/completed_stages"
  echo "" > "$DISPLAY_STATE_DIR/activity"
}

# ─────────────────────────────────────────────────────────────────────────────
# Activity Feed
# ─────────────────────────────────────────────────────────────────────────────

add_activity() {
  local type="$1"
  local detail="$2"

  local prefix=""
  case "$type" in
    read)   prefix="read   " ;;
    write)  prefix="write  " ;;
    edit)   prefix="edit   " ;;
    commit) prefix="commit " ;;
    test)   prefix="test   " ;;
    *)      prefix="       " ;;
  esac

  # Truncate long paths/messages
  if [ ${#detail} -gt 50 ]; then
    detail="${detail:0:47}..."
  fi

  # Append to activity file, keep last N lines
  echo "$prefix $detail" >> "$DISPLAY_STATE_DIR/activity"
  tail -n $MAX_ACTIVITY_LINES "$DISPLAY_STATE_DIR/activity" > "$DISPLAY_STATE_DIR/activity.tmp"
  mv "$DISPLAY_STATE_DIR/activity.tmp" "$DISPLAY_STATE_DIR/activity"
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase Context
# ─────────────────────────────────────────────────────────────────────────────

CURRENT_PHASE=""
CURRENT_PHASE_NAME=""
CURRENT_PHASE_CONTEXT=""

load_phase_context() {
  local phase="$1"
  local roadmap=".planning/ROADMAP.md"

  [ ! -f "$roadmap" ] && return

  # Extract phase name
  CURRENT_PHASE_NAME=$(grep -E "Phase $phase:" "$roadmap" 2>/dev/null | head -1 | sed 's/.*Phase [0-9]*: //' | sed 's/ *$//' | sed 's/\*//g')
  [ -z "$CURRENT_PHASE_NAME" ] && CURRENT_PHASE_NAME="Phase $phase"

  # Extract goal and deliverables
  local in_phase=0
  local context=""
  local line_count=0

  while IFS= read -r line; do
    if echo "$line" | grep -qE "Phase $phase:"; then
      in_phase=1
      continue
    fi

    if [ $in_phase -eq 1 ]; then
      # Stop at next phase
      if echo "$line" | grep -qE "^###.*Phase [0-9]"; then
        break
      fi

      # Capture goal
      if echo "$line" | grep -q "Goal:"; then
        context=$(echo "$line" | sed 's/.*Goal:[[:space:]]*//' | sed 's/\*//g')
      fi

      # Capture must-haves (first few)
      if echo "$line" | grep -qE "^[[:space:]]*-[[:space:]]" && [ $line_count -lt 4 ]; then
        local item=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/\*//g')
        if [ -n "$item" ]; then
          context="$context
  $item"
          ((line_count++))
        fi
      fi
    fi
  done < "$roadmap"

  CURRENT_PHASE_CONTEXT="$context"
}

# ─────────────────────────────────────────────────────────────────────────────
# Display Rendering
# ─────────────────────────────────────────────────────────────────────────────

render_display() {
  local total_phases=$1
  local current_idx=$2

  # Read current state from files
  local current_stage=$(cat "$DISPLAY_STATE_DIR/current_stage" 2>/dev/null)
  local stage_desc=$(cat "$DISPLAY_STATE_DIR/stage_desc" 2>/dev/null)
  local stage_start=$(cat "$DISPLAY_STATE_DIR/stage_start" 2>/dev/null)

  # Header
  printf "${C_BOLD}${C_CYAN}"
  printf "═══════════════════════════════════════════════════════════════\n"
  printf " GSD AUTOPILOT"
  printf "%*s" $((46 - ${#PROJECT_NAME})) ""
  printf "Phase %s/%s\n" "$((current_idx + 1))" "$total_phases"
  printf "═══════════════════════════════════════════════════════════════${C_RESET}\n"
  printf "\n"

  # Phase info
  printf " ${C_BOLD}${C_WHITE}PHASE %s: %s${C_RESET}\n" "$CURRENT_PHASE" "$CURRENT_PHASE_NAME"
  printf "\n"

  # Phase context (if available)
  if [ -n "$CURRENT_PHASE_CONTEXT" ]; then
    echo "$CURRENT_PHASE_CONTEXT" | head -5 | while IFS= read -r line; do
      printf "${C_DIM} %s${C_RESET}\n" "$line"
    done
    printf "\n"
  fi

  printf "${C_DIM}───────────────────────────────────────────────────────────────${C_RESET}\n"
  printf "\n"

  # Completed stages
  if [ -f "$DISPLAY_STATE_DIR/completed_stages" ]; then
    while IFS= read -r stage_entry; do
      [ -z "$stage_entry" ] && continue
      local stage_name="${stage_entry%%:*}"
      local stage_time="${stage_entry##*:}"
      printf " ${C_DIM}%-12s%47s${C_RESET}\n" "$stage_name" "done $stage_time"
    done < "$DISPLAY_STATE_DIR/completed_stages"
  fi

  # Current stage
  if [ -n "$current_stage" ]; then
    local elapsed=""
    if [ -n "$stage_start" ] && [ "$stage_start" != "0" ]; then
      elapsed=$(elapsed_since "$stage_start")
    fi
    printf " ${C_WHITE}${C_BOLD}%-12s${C_RESET}%47s\n" "$current_stage" "$elapsed"

    if [ -n "$stage_desc" ]; then
      # Truncate description if needed
      local desc="$stage_desc"
      if [ ${#desc} -gt 55 ]; then
        desc="${desc:0:52}..."
      fi
      printf "\n"
      printf "${C_DIM}   %s${C_RESET}\n" "$desc"
    fi
  fi

  printf "\n"
  printf "${C_DIM}───────────────────────────────────────────────────────────────${C_RESET}\n"
  printf "\n"

  # Activity feed
  printf " ${C_DIM}Activity:${C_RESET}\n"
  printf "\n"

  local activity_count=0
  if [ -f "$DISPLAY_STATE_DIR/activity" ] && [ -s "$DISPLAY_STATE_DIR/activity" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      printf "${C_DIM}   %s${C_RESET}\n" "$line"
      ((activity_count++))
    done < "$DISPLAY_STATE_DIR/activity"
  fi

  if [ $activity_count -eq 0 ]; then
    printf "${C_DIM}   waiting...${C_RESET}\n"
    activity_count=1
  fi

  # Pad to consistent height
  local pad_lines=$((MAX_ACTIVITY_LINES - activity_count))
  for ((i=0; i<pad_lines; i++)); do
    printf "\n"
  done

  printf "\n"
  printf "${C_DIM}───────────────────────────────────────────────────────────────${C_RESET}\n"
  printf "\n"

  # Progress bar
  local completed=$current_idx
  local bar_width=50
  local filled=$((completed * bar_width / total_phases))
  local empty=$((bar_width - filled))

  printf " Progress ["
  printf "${C_CYAN}"
  for ((i=0; i<filled; i++)); do printf "="; done
  for ((i=0; i<empty; i++)); do printf " "; done
  printf "${C_RESET}"
  printf "] %d/%d phases\n" "$completed" "$total_phases"

  printf "\n"
  printf "${C_DIM}───────────────────────────────────────────────────────────────${C_RESET}\n"
}

# ─────────────────────────────────────────────────────────────────────────────
# Activity Pipe Reader (runs in background)
# ─────────────────────────────────────────────────────────────────────────────

READER_PID=""
DISPLAY_PID=""

start_activity_reader() {
  local total_phases=$1
  local phase_idx=$2

  # Background process to read from pipe and update state
  (
    while true; do
      if read -r line < "$ACTIVITY_PIPE" 2>/dev/null; then
        case "$line" in
          STAGE:*)
            local type=$(echo "$line" | cut -d: -f2)
            local desc=$(echo "$line" | cut -d: -f3-)
            set_stage "$type" "$desc"
            ;;
          FILE:*)
            local op=$(echo "$line" | cut -d: -f2)
            local file=$(echo "$line" | cut -d: -f3-)
            add_activity "$op" "$file"
            ;;
          COMMIT:*)
            local msg=$(echo "$line" | cut -d: -f2-)
            add_activity "commit" "$msg"
            ;;
          TEST:*)
            add_activity "test" "running tests"
            ;;
          TODO:*)
            local task=$(echo "$line" | cut -d: -f2-)
            echo "$task" > "$DISPLAY_STATE_DIR/stage_desc"
            ;;
        esac
      fi
    done
  ) &
  READER_PID=$!

  # Background process to refresh display
  if [ -t 1 ]; then
    (
      while true; do
        printf "${CURSOR_HOME}${CURSOR_CLEAR}"
        render_display "$total_phases" "$phase_idx"
        sleep 0.5
      done
    ) &
    DISPLAY_PID=$!
  fi
}

stop_activity_reader() {
  if [ -n "$READER_PID" ]; then
    kill $READER_PID 2>/dev/null || true
    wait $READER_PID 2>/dev/null || true
    READER_PID=""
  fi
  if [ -n "$DISPLAY_PID" ]; then
    kill $DISPLAY_PID 2>/dev/null || true
    wait $DISPLAY_PID 2>/dev/null || true
    DISPLAY_PID=""
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Logging & Notifications
# ─────────────────────────────────────────────────────────────────────────────

log() {
  local level="$1"
  local message="$2"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  # Always write to log file
  echo "[$timestamp] [$level] $message" >> "$LOG_DIR/autopilot.log"
}

notify() {
  local message="$1"
  local status="${2:-info}"

  log "NOTIFY" "$message"

  # Terminal bell
  printf "\a"

  # Webhook if configured
  if [ -n "$WEBHOOK_URL" ]; then
    curl -s -X POST "$WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -d "{\"text\": \"GSD Autopilot [$PROJECT_NAME]: $message\", \"status\": \"$status\"}" \
      > /dev/null 2>&1 || true
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Git Safety
# ─────────────────────────────────────────────────────────────────────────────

check_uncommitted_files() {
  local context="$1"

  # Check for uncommitted changes
  if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    local uncommitted=$(git status --short 2>/dev/null)

    log "WARN" "Uncommitted files detected ($context)"
    log "WARN" "$uncommitted"

    # Create safety commit
    git add -A 2>/dev/null
    git commit -m "wip(autopilot): uncommitted files from $context

Autopilot detected uncommitted files that would otherwise be lost.
Review and squash/revert as appropriate.
" 2>/dev/null || true

    log "INFO" "Created safety commit for orphaned files"
    add_activity "commit" "wip: safety commit"
    return 1
  fi
  return 0
}

ensure_clean_working_tree() {
  local context="$1"
  check_uncommitted_files "$context" || true
}

# ─────────────────────────────────────────────────────────────────────────────
# State Management
# ─────────────────────────────────────────────────────────────────────────────

update_autopilot_state() {
  local mode="$1"
  local phase="$2"
  local remaining="$3"
  local error="${4:-none}"

  if grep -q "## Autopilot" "$STATE_FILE" 2>/dev/null; then
    awk -v mode="$mode" -v phase="$phase" -v remaining="$remaining" -v error="$error" -v ts="$(iso_timestamp)" '
      /^## Autopilot/,/^## / {
        if (/^- \*\*Mode:\*\*/) { print "- **Mode:** " mode; next }
        if (/^- \*\*Current Phase:\*\*/) { print "- **Current Phase:** " phase; next }
        if (/^- \*\*Phases Remaining:\*\*/) { print "- **Phases Remaining:** " remaining; next }
        if (/^- \*\*Last Error:\*\*/) { print "- **Last Error:** " error; next }
        if (/^- \*\*Updated:\*\*/) { print "- **Updated:** " ts; next }
      }
      { print }
    ' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
  else
    cat >> "$STATE_FILE" << EOF

## Autopilot

- **Mode:** $mode
- **Started:** $(iso_timestamp)
- **Current Phase:** $phase
- **Phases Remaining:** $remaining
- **Checkpoints Pending:** (none)
- **Last Error:** $error
- **Updated:** $(iso_timestamp)
EOF
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Cost Tracking
# ─────────────────────────────────────────────────────────────────────────────

TOTAL_TOKENS=0
TOTAL_COST_CENTS=0

track_cost() {
  local log_file="$1"
  local phase="$2"

  local tokens=$(grep -o 'tokens[: ]*[0-9,]*' "$log_file" 2>/dev/null | tail -1 | grep -o '[0-9]*' | tr -d ',' || echo "0")

  if [ "$tokens" -gt 0 ]; then
    TOTAL_TOKENS=$((TOTAL_TOKENS + tokens))

    local cost_cents=$((tokens / 100))
    TOTAL_COST_CENTS=$((TOTAL_COST_CENTS + cost_cents))

    local total_dollars=$((TOTAL_COST_CENTS / 100))
    local total_remainder=$((TOTAL_COST_CENTS % 100))
    local total_cost=$(printf "%d.%02d" $total_dollars $total_remainder)

    log "COST" "Phase $phase: ${tokens} tokens (~\$${total_cost} total)"
  fi

  # Budget check
  if [ "$BUDGET_LIMIT" -gt 0 ]; then
    local budget_cents=$((BUDGET_LIMIT * 100))
    if [ "$TOTAL_COST_CENTS" -gt "$budget_cents" ]; then
      local total_dollars=$((TOTAL_COST_CENTS / 100))
      local total_remainder=$((TOTAL_COST_CENTS % 100))
      local total_cost=$(printf "%d.%02d" $total_dollars $total_remainder)
      notify "Budget exceeded: \$${total_cost} / \$${BUDGET_LIMIT}" "error"
      update_autopilot_state "paused" "$phase" "${PHASES[*]}" "budget_exceeded"
      exit 0
    fi

    local warning_threshold=$((budget_cents * 80 / 100))
    if [ "$TOTAL_COST_CENTS" -gt "$warning_threshold" ]; then
      notify "Budget warning: 80% used" "warning"
    fi
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Checkpoint Handling
# ─────────────────────────────────────────────────────────────────────────────

queue_checkpoint() {
  local phase="$1"
  local plan="$2"
  local checkpoint_data="$3"

  local checkpoint_file="$CHECKPOINT_DIR/pending/phase-${phase}-plan-${plan}.json"
  echo "$checkpoint_data" > "$checkpoint_file"

  log "CHECKPOINT" "Queued: $checkpoint_file"
  notify "Checkpoint queued: Phase $phase, Plan $plan" "checkpoint"
}

process_approved_checkpoints() {
  mkdir -p "$CHECKPOINT_DIR/processed"

  for approval in "$CHECKPOINT_DIR/approved/"*.json; do
    [ -f "$approval" ] || continue

    if grep -q '"approved": false' "$approval" 2>/dev/null; then
      log "INFO" "Checkpoint rejected, skipping: $approval"
      mv "$approval" "$CHECKPOINT_DIR/processed/"
      continue
    fi

    local basename=$(basename "$approval" .json)
    local phase=$(echo "$basename" | sed -n 's/phase-\([0-9]*\)-.*/\1/p')
    local plan=$(echo "$basename" | sed -n 's/.*plan-\([0-9]*\)/\1/p')

    if [ -z "$phase" ] || [ -z "$plan" ]; then
      log "WARN" "Could not parse phase/plan from: $approval"
      mv "$approval" "$CHECKPOINT_DIR/processed/"
      continue
    fi

    log "INFO" "Processing approved checkpoint: Phase $phase, Plan $plan"

    local user_response=$(grep -o '"response"[[:space:]]*:[[:space:]]*"[^"]*"' "$approval" | sed 's/.*: *"//' | sed 's/"$//' || echo "")
    local continuation_log="$LOG_DIR/continuation-phase${phase}-plan${plan}-$(date +%Y%m%d-%H%M%S).log"

    add_activity "commit" "continuing from checkpoint"

    echo "/gsd:execute-plan $phase $plan --continue --checkpoint-response \"$user_response\"" | claude -p \
        --allowedTools "Read,Write,Edit,Glob,Grep,Bash,Task,TodoWrite,AskUserQuestion" \
        2>&1 | tee -a "$continuation_log"

    if [ ${PIPESTATUS[1]} -ne 0 ]; then
      log "ERROR" "Continuation failed"
    else
      mv "$approval" "$CHECKPOINT_DIR/processed/"
      track_cost "$continuation_log" "$phase"
    fi
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase Execution
# ─────────────────────────────────────────────────────────────────────────────

is_phase_complete() {
  local phase="$1"
  grep -qE "^- \[x\] \*\*Phase $phase" .planning/ROADMAP.md 2>/dev/null
}

execute_phase() {
  local phase="$1"
  local phase_idx="$2"
  local total_phases="$3"
  local attempt=1
  local phase_log="$LOG_DIR/phase-${phase}-$(date +%Y%m%d-%H%M%S).log"

  # Safety check before starting
  ensure_clean_working_tree "before phase $phase"

  # Skip completed phases
  if is_phase_complete "$phase"; then
    log "INFO" "Phase $phase already complete, skipping"
    return 0
  fi

  # Load phase context
  CURRENT_PHASE="$phase"
  load_phase_context "$phase"
  reset_stages

  # Start activity reader and display
  start_activity_reader "$total_phases" "$phase_idx"

  # Initial render (hide cursor for clean display)
  if [ -t 1 ]; then
    printf "${CURSOR_HIDE}${CURSOR_HOME}${CURSOR_CLEAR}"
    render_display "$total_phases" "$phase_idx"
  fi

  while [ $attempt -le $MAX_RETRIES ]; do
    if [ $attempt -gt 1 ]; then
      log "INFO" "Retry $attempt/$MAX_RETRIES for phase $phase"
      add_activity "retry" "attempt $attempt of $MAX_RETRIES"
    fi

    # Check if phase needs planning
    local phase_dir=$(ls -d .planning/phases/$(printf "%02d" "$phase" 2>/dev/null || echo "$phase")-* 2>/dev/null | head -1)

    if [ -z "$phase_dir" ] || [ $(ls "$phase_dir"/*-PLAN.md 2>/dev/null | wc -l) -eq 0 ]; then
      log "INFO" "Planning phase $phase"

      echo "/gsd:plan-phase $phase" | claude -p \
          --allowedTools "Read,Write,Edit,Glob,Grep,Bash,Task,TodoWrite,AskUserQuestion" \
          2>&1 | tee -a "$phase_log"

      if [ ${PIPESTATUS[1]} -ne 0 ]; then
        log "ERROR" "Planning failed for phase $phase"
        ((attempt++))
        sleep 5
        continue
      fi

      phase_dir=$(ls -d .planning/phases/$(printf "%02d" "$phase" 2>/dev/null || echo "$phase")-* 2>/dev/null | head -1)
    fi

    # Execution
    log "INFO" "Executing phase $phase"

    echo "/gsd:execute-phase $phase" | claude -p \
        --allowedTools "Read,Write,Edit,Glob,Grep,Bash,Task,TodoWrite,AskUserQuestion" \
        2>&1 | tee -a "$phase_log"

    if [ ${PIPESTATUS[1]} -ne 0 ]; then
      log "ERROR" "Execution failed for phase $phase"
      ((attempt++))
      sleep 5
      continue
    fi

    track_cost "$phase_log" "$phase"

    # Check verification status
    local verification_file=$(ls "$phase_dir"/*-VERIFICATION.md 2>/dev/null | head -1)
    local status="passed"

    if [ -f "$verification_file" ]; then
      status=$(grep "^status:" "$verification_file" | head -1 | cut -d: -f2 | tr -d ' ')
    fi

    case "$status" in
      "passed")
        complete_current_stage
        stop_activity_reader
        ensure_clean_working_tree "after phase $phase"
        notify "Phase $phase complete" "success"
        return 0
        ;;

      "gaps_found")
        log "INFO" "Gaps found in phase $phase, planning closure"

        echo "/gsd:plan-phase $phase --gaps" | claude -p \
            --allowedTools "Read,Write,Edit,Glob,Grep,Bash,Task,TodoWrite,AskUserQuestion" \
            2>&1 | tee -a "$phase_log"

        if [ ${PIPESTATUS[1]} -ne 0 ]; then
          ((attempt++))
          continue
        fi

        echo "/gsd:execute-phase $phase --gaps-only" | claude -p \
            --allowedTools "Read,Write,Edit,Glob,Grep,Bash,Task,TodoWrite,AskUserQuestion" \
            2>&1 | tee -a "$phase_log"

        if [ ${PIPESTATUS[1]} -ne 0 ]; then
          ((attempt++))
          continue
        fi

        track_cost "$phase_log" "$phase"

        status=$(grep "^status:" "$verification_file" 2>/dev/null | tail -1 | cut -d: -f2 | tr -d ' ')

        if [ "$status" = "passed" ]; then
          complete_current_stage
          stop_activity_reader
          ensure_clean_working_tree "after phase $phase gap closure"
          notify "Phase $phase complete (after gap closure)" "success"
          return 0
        else
          ((attempt++))
          continue
        fi
        ;;

      "human_needed")
        if [ "$CHECKPOINT_MODE" = "queue" ]; then
          queue_checkpoint "$phase" "verification" "{\"type\": \"human_verification\", \"phase\": \"$phase\"}"
        fi
        complete_current_stage
        stop_activity_reader
        ensure_clean_working_tree "after phase $phase (human verification queued)"
        return 0
        ;;

      *)
        complete_current_stage
        stop_activity_reader
        ensure_clean_working_tree "after phase $phase"
        return 0
        ;;
    esac
  done

  # All retries exhausted
  stop_activity_reader
  ensure_clean_working_tree "after phase $phase failure"
  notify "Phase $phase FAILED after $MAX_RETRIES attempts" "error"
  return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
  local total_phases=${#PHASES[@]}
  local start_time=$(date +%s)

  # Startup banner
  clear 2>/dev/null || true

  printf "\n"
  printf "${C_BOLD}${C_CYAN}"
  printf "   ██████╗ ███████╗██████╗ \n"
  printf "  ██╔════╝ ██╔════╝██╔══██╗\n"
  printf "  ██║  ███╗███████╗██║  ██║\n"
  printf "  ██║   ██║╚════██║██║  ██║\n"
  printf "  ╚██████╔╝███████║██████╔╝\n"
  printf "   ╚═════╝ ╚══════╝╚═════╝ \n"
  printf "${C_RESET}\n"
  printf "${C_BOLD}${C_WHITE}  AUTOPILOT${C_RESET}\n"
  printf "${C_DIM}  %s${C_RESET}\n" "$PROJECT_NAME"
  printf "\n"
  printf "${C_DIM}  Phases:      %s${C_RESET}\n" "${PHASES[*]}"
  printf "${C_DIM}  Retries:     %s per phase${C_RESET}\n" "$MAX_RETRIES"
  printf "${C_DIM}  Budget:      \$%s${C_RESET}\n" "$BUDGET_LIMIT"
  printf "${C_DIM}  Checkpoints: %s${C_RESET}\n" "$CHECKPOINT_MODE"
  printf "\n"
  printf "${C_DIM}  Starting in 3 seconds...${C_RESET}\n"

  sleep 3

  log "INFO" "Autopilot started for $PROJECT_NAME"
  notify "Autopilot started" "info"

  local remaining_phases=("${PHASES[@]}")
  local phase_idx=0

  for phase in "${PHASES[@]}"; do
    process_approved_checkpoints

    remaining_phases=("${remaining_phases[@]:1}")
    local remaining_str="${remaining_phases[*]:-none}"

    update_autopilot_state "running" "$phase" "$remaining_str"

    if ! execute_phase "$phase" "$phase_idx" "$total_phases"; then
      update_autopilot_state "failed" "$phase" "$remaining_str" "phase_${phase}_failed"

      if [ -t 1 ]; then
        printf "${CURSOR_SHOW}"
        printf "\n${C_RED}${C_BOLD}Autopilot stopped at phase $phase${C_RESET}\n"
      fi

      notify "Autopilot STOPPED at phase $phase" "error"
      exit 1
    fi

    ((phase_idx++))
  done

  # Final checkpoint processing
  process_approved_checkpoints

  # Final safety check
  ensure_clean_working_tree "autopilot completion"

  # Completion
  local total_time=$(($(date +%s) - start_time))
  local total_min=$((total_time / 60))
  local total_sec=$((total_time % 60))

  local total_dollars=$((TOTAL_COST_CENTS / 100))
  local total_remainder=$((TOTAL_COST_CENTS % 100))
  local total_cost=$(printf "%d.%02d" $total_dollars $total_remainder)

  update_autopilot_state "completed" "all" "none"

  if [ -t 1 ]; then
    printf "${CURSOR_SHOW}"
    clear

    printf "\n"
    printf "${C_BOLD}${C_GREEN}"
    printf "  ╔═══════════════════════════════════════════════════╗\n"
    printf "  ║              MILESTONE COMPLETE                   ║\n"
    printf "  ╚═══════════════════════════════════════════════════╝\n"
    printf "${C_RESET}\n"

    printf "${C_WHITE}  Phases:${C_RESET}    %d completed\n" "$total_phases"
    printf "${C_WHITE}  Time:${C_RESET}      %dm %ds\n" "$total_min" "$total_sec"
    printf "${C_WHITE}  Tokens:${C_RESET}    %s\n" "$TOTAL_TOKENS"
    printf "${C_WHITE}  Cost:${C_RESET}      \$%s\n" "$total_cost"
    printf "\n"
  fi

  log "SUCCESS" "Milestone complete: $total_phases phases, ${total_min}m ${total_sec}s, \$$total_cost"

  # Complete milestone
  echo "/gsd:complete-milestone" | claude -p \
    --allowedTools "Read,Write,Edit,Glob,Grep,Bash,AskUserQuestion" \
    2>&1 | tee -a "$LOG_DIR/milestone-complete.log"

  notify "Milestone COMPLETE! $total_phases phases, \$$total_cost" "success"

  # Check for pending checkpoints
  local pending_count=$(ls "$CHECKPOINT_DIR/pending/"*.json 2>/dev/null | wc -l | tr -d ' ')
  if [ "$pending_count" -gt 0 ]; then
    printf "\n"
    printf "${C_YELLOW}  Pending checkpoints: %d${C_RESET}\n" "$pending_count"
    printf "${C_DIM}  Run: /gsd:checkpoints${C_RESET}\n"
  fi

  printf "\n"
  printf "${C_DIM}  Logs: %s/${C_RESET}\n" "$LOG_DIR"
  printf "\n"
}

# ─────────────────────────────────────────────────────────────────────────────
# Run
# ─────────────────────────────────────────────────────────────────────────────

main "$@"
