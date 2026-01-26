#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# GSD Autopilot Script
# Generated: {{timestamp}}
# Project: {{project_name}}
# ═══════════════════════════════════════════════════════════════════════════════
#
# This script autonomously executes all remaining phases in the milestone.
# Each phase gets fresh 200k context via claude -p.
# State persists in .planning/ - safe to interrupt and resume.
#
# Usage:
#   bash .planning/autopilot.sh              # Run attached
#   nohup bash .planning/autopilot.sh &      # Run in background
#
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Signal to GSD commands that we're in autopilot mode
# Commands will suppress "Next Up" guidance and use plain text output
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
# Note: Lock uses directory (atomic mkdir) not file - see LOCK_DIR below

# ─────────────────────────────────────────────────────────────────────────────
# Setup
# ─────────────────────────────────────────────────────────────────────────────

cd "$PROJECT_DIR"
mkdir -p "$LOG_DIR" "$CHECKPOINT_DIR/pending" "$CHECKPOINT_DIR/approved"

# Lock directory (atomic creation prevents race condition)
LOCK_DIR="$PROJECT_DIR/.planning/autopilot.lock.d"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "ERROR: Autopilot already running (lock exists: $LOCK_DIR)"
  echo "If previous run crashed, remove manually: rmdir '$LOCK_DIR'"
  exit 1
fi
trap "rmdir '$LOCK_DIR' 2>/dev/null" EXIT INT TERM

# ─────────────────────────────────────────────────────────────────────────────
# Cross-platform helpers
# ─────────────────────────────────────────────────────────────────────────────

# ISO timestamp (works on both GNU and BSD date)
iso_timestamp() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

# Safe arithmetic that doesn't require bc
# Usage: safe_calc "expression" (supports +, -, *, / with integers)
# For decimals, falls back to bc if available, otherwise integer approximation
safe_calc() {
  local expr="$1"
  if command -v bc &>/dev/null; then
    echo "$expr" | bc
  else
    # Integer-only fallback (loses decimal precision)
    echo $(( ${expr%.*} ))
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Terminal UI Helpers
# ─────────────────────────────────────────────────────────────────────────────

# Colors (auto-disabled if not a terminal)
if [ -t 1 ]; then
  C_RESET='\033[0m'
  C_BOLD='\033[1m'
  C_DIM='\033[2m'
  C_RED='\033[31m'
  C_GREEN='\033[32m'
  C_YELLOW='\033[33m'
  C_BLUE='\033[34m'
  C_MAGENTA='\033[35m'
  C_CYAN='\033[36m'
  C_WHITE='\033[37m'
  # Cursor control
  CURSOR_UP='\033[1A'
  CURSOR_CLEAR='\033[K'
  CURSOR_HIDE='\033[?25l'
  CURSOR_SHOW='\033[?25h'
else
  C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW=''
  C_BLUE='' C_MAGENTA='' C_CYAN='' C_WHITE=''
  CURSOR_UP='' CURSOR_CLEAR='' CURSOR_HIDE='' CURSOR_SHOW=''
fi

# Spinner frames (works in any terminal)
SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
SPINNER_PID=""

# Start spinner with message
start_spinner() {
  local msg="$1"

  # Don't start if not a terminal or already running
  [ -t 1 ] || return 0
  [ -n "$SPINNER_PID" ] && return 0

  (
    local i=0
    while true; do
      printf "\r${C_CYAN}${SPINNER_FRAMES[$i]}${C_RESET} ${C_DIM}%s${C_RESET}${CURSOR_CLEAR}" "$msg"
      i=$(( (i + 1) % ${#SPINNER_FRAMES[@]} ))
      sleep 0.1
    done
  ) &
  SPINNER_PID=$!
  disown $SPINNER_PID 2>/dev/null
}

# Stop spinner and show result
stop_spinner() {
  local result="${1:-done}"  # done, error, skip
  local msg="${2:-}"

  if [ -n "$SPINNER_PID" ]; then
    kill $SPINNER_PID 2>/dev/null
    wait $SPINNER_PID 2>/dev/null
    SPINNER_PID=""
  fi

  # Clear spinner line
  printf "\r${CURSOR_CLEAR}"

  # Show result
  case "$result" in
    done)   printf "${C_GREEN}✓${C_RESET} %s\n" "$msg" ;;
    error)  printf "${C_RED}✗${C_RESET} %s\n" "$msg" ;;
    skip)   printf "${C_YELLOW}○${C_RESET} %s\n" "$msg" ;;
    *)      printf "  %s\n" "$msg" ;;
  esac
}

# Progress bar
progress_bar() {
  local current=$1
  local total=$2
  local width=${3:-30}
  local label="${4:-}"

  local percent=$((current * 100 / total))
  local filled=$((current * width / total))
  local empty=$((width - filled))

  local bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done

  printf "\r${C_BOLD}%s${C_RESET} [${C_CYAN}%s${C_RESET}] %3d%% " "$label" "$bar" "$percent"
}

# Styled section header
section_header() {
  local title="$1"
  local subtitle="${2:-}"

  echo ""
  printf "${C_BOLD}${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
  printf "${C_BOLD}${C_WHITE} GSD ► %s${C_RESET}\n" "$title"
  if [ -n "$subtitle" ]; then
    printf "${C_DIM} %s${C_RESET}\n" "$subtitle"
  fi
  printf "${C_BOLD}${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
  echo ""
}

# Status line (updates in place)
status_line() {
  local phase="$1"
  local stage="$2"
  local detail="${3:-}"

  if [ -t 1 ]; then
    printf "\r${CURSOR_CLEAR}${C_DIM}Phase %s${C_RESET} │ ${C_CYAN}%s${C_RESET}" "$phase" "$stage"
    [ -n "$detail" ] && printf " ${C_DIM}%s${C_RESET}" "$detail"
  fi
}

# Cleanup on exit (ensure cursor visible)
cleanup_ui() {
  [ -n "$SPINNER_PID" ] && kill $SPINNER_PID 2>/dev/null
  printf "${CURSOR_SHOW}" 2>/dev/null
}
trap cleanup_ui EXIT

# ─────────────────────────────────────────────────────────────────────────────
# Logging & Notifications
# ─────────────────────────────────────────────────────────────────────────────

log() {
  local level="$1"
  local message="$2"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  # Always write to log file (no colors)
  echo "[$timestamp] [$level] $message" >> "$LOG_DIR/autopilot.log"

  # Terminal output with colors
  local color=""
  local icon=""
  case "$level" in
    INFO)    color="$C_BLUE";   icon="ℹ" ;;
    SUCCESS) color="$C_GREEN";  icon="✓" ;;
    WARN)    color="$C_YELLOW"; icon="⚠" ;;
    ERROR)   color="$C_RED";    icon="✗" ;;
    FATAL)   color="$C_RED";    icon="☠" ;;
    COST)    color="$C_MAGENTA"; icon="$" ;;
    *)       color="$C_DIM";    icon="•" ;;
  esac

  printf "${color}${icon}${C_RESET} ${C_DIM}%s${C_RESET} %s\n" "[$timestamp]" "$message"
}

banner() {
  section_header "$1"
}

notify() {
  local message="$1"
  local status="${2:-info}"

  log "NOTIFY" "$message"

  # Terminal bell
  echo -e "\a"

  # Webhook if configured
  if [ -n "$WEBHOOK_URL" ]; then
    curl -s -X POST "$WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -d "{\"text\": \"GSD Autopilot [$PROJECT_NAME]: $message\", \"status\": \"$status\"}" \
      > /dev/null 2>&1 || true
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# State Management
# ─────────────────────────────────────────────────────────────────────────────

update_autopilot_state() {
  local mode="$1"
  local phase="$2"
  local remaining="$3"
  local error="${4:-none}"

  # Update or create Autopilot section in STATE.md
  if grep -q "## Autopilot" "$STATE_FILE" 2>/dev/null; then
    # Update existing section (using temp file for portability)
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
    # Append new section
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
TOTAL_COST="0.00"
TOTAL_COST_CENTS=0

track_cost() {
  local log_file="$1"
  local phase="$2"

  # Try to extract token count from log (format varies by claude version)
  local tokens=$(grep -o 'tokens[: ]*[0-9,]*' "$log_file" 2>/dev/null | tail -1 | grep -o '[0-9]*' | tr -d ',' || echo "0")

  if [ "$tokens" -gt 0 ]; then
    TOTAL_TOKENS=$((TOTAL_TOKENS + tokens))

    # Cost estimate: ~$0.01 per 1000 tokens (rough average)
    # Using integer math: cost in cents = tokens / 100, then convert to dollars
    local cost_cents=$((tokens / 100))
    local cost_dollars=$((cost_cents / 100))
    local cost_remainder=$((cost_cents % 100))
    local cost=$(printf "%d.%02d" $cost_dollars $cost_remainder)

    # Accumulate total (in cents for precision)
    TOTAL_COST_CENTS=$((TOTAL_COST_CENTS + cost_cents))
    local total_dollars=$((TOTAL_COST_CENTS / 100))
    local total_remainder=$((TOTAL_COST_CENTS % 100))
    TOTAL_COST=$(printf "%d.%02d" $total_dollars $total_remainder)

    log "COST" "Phase $phase: ${tokens} tokens (~\$${cost})"
  fi

  # Budget check (convert budget to cents for comparison)
  if [ "$BUDGET_LIMIT" -gt 0 ]; then
    local budget_cents=$((BUDGET_LIMIT * 100))
    if [ "$TOTAL_COST_CENTS" -gt "$budget_cents" ]; then
      notify "Budget exceeded: \$${TOTAL_COST} / \$${BUDGET_LIMIT}" "error"
      update_autopilot_state "paused" "$phase" "${PHASES[*]}" "budget_exceeded"
      exit 0
    fi

    # Warning at 80%
    local warning_threshold=$((budget_cents * 80 / 100))
    if [ "$TOTAL_COST_CENTS" -gt "$warning_threshold" ]; then
      notify "Budget warning: \$${TOTAL_COST} / \$${BUDGET_LIMIT} (80%)" "warning"
    fi
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Checkpoint Handling
# ─────────────────────────────────────────────────────────────────────────────

check_pending_approvals() {
  local phase="$1"

  # Look for approved checkpoints for this phase
  for approval in "$CHECKPOINT_DIR/approved/phase-${phase}-"*.json; do
    if [ -f "$approval" ]; then
      log "INFO" "Found approval: $approval"
      return 0
    fi
  done
  return 1
}

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
  # Process any approved checkpoints by spawning continuation agents
  mkdir -p "$CHECKPOINT_DIR/processed"

  for approval in "$CHECKPOINT_DIR/approved/"*.json; do
    [ -f "$approval" ] || continue

    # Check if actually approved (not rejected)
    if grep -q '"approved": false' "$approval" 2>/dev/null; then
      log "INFO" "Checkpoint rejected, skipping: $approval"
      mv "$approval" "$CHECKPOINT_DIR/processed/"
      continue
    fi

    # Extract phase and plan from filename (e.g., phase-03-plan-02.json)
    local basename=$(basename "$approval" .json)
    local phase=$(echo "$basename" | sed -n 's/phase-\([0-9]*\)-.*/\1/p')
    local plan=$(echo "$basename" | sed -n 's/.*plan-\([0-9]*\)/\1/p')

    if [ -z "$phase" ] || [ -z "$plan" ]; then
      log "WARN" "Could not parse phase/plan from: $approval"
      mv "$approval" "$CHECKPOINT_DIR/processed/"
      continue
    fi

    log "INFO" "Processing approved checkpoint: Phase $phase, Plan $plan"

    # Extract user response from approval file
    local user_response=$(grep -o '"response"[[:space:]]*:[[:space:]]*"[^"]*"' "$approval" | sed 's/.*: *"//' | sed 's/"$//' || echo "")

    # Spawn continuation agent
    local continuation_log="$LOG_DIR/continuation-phase${phase}-plan${plan}-$(date +%Y%m%d-%H%M%S).log"

    printf "\n${C_CYAN}◆${C_RESET} Continuing Phase %s, Plan %s ${C_DIM}(checkpoint approved)${C_RESET}\n\n" "$phase" "$plan"

    start_spinner "Resuming from checkpoint..."

    # Pass the checkpoint context and user response to continuation
    echo "/gsd:execute-plan $phase $plan --continue --checkpoint-response \"$user_response\"" | claude -p \
        --allowedTools "Read,Write,Edit,Glob,Grep,Bash,Task,TodoWrite,AskUserQuestion" \
        2>&1 | tee -a "$continuation_log"

    if [ ${PIPESTATUS[1]} -ne 0 ]; then
      stop_spinner "error" "Continuation failed"
      # Don't move to processed - will retry on next run
    else
      stop_spinner "done" "Checkpoint complete"
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
  # Check ROADMAP.md for [x] marker on this phase
  if grep -qE "^- \[x\] \*\*Phase $phase" .planning/ROADMAP.md 2>/dev/null; then
    return 0
  fi
  return 1
}

execute_phase() {
  local phase="$1"
  local attempt=1
  local phase_log="$LOG_DIR/phase-${phase}-$(date +%Y%m%d-%H%M%S).log"

  # Skip already-completed phases (idempotency on resume)
  if is_phase_complete "$phase"; then
    stop_spinner "skip" "Phase $phase already complete"
    return 0
  fi

  # Get phase name from roadmap
  local phase_name=$(grep -E "Phase $phase:" .planning/ROADMAP.md 2>/dev/null | sed 's/.*Phase [0-9]*: //' | head -1)
  [ -z "$phase_name" ] && phase_name="Unknown"

  section_header "PHASE $phase" "$phase_name"

  while [ $attempt -le $MAX_RETRIES ]; do
    [ $attempt -gt 1 ] && printf "${C_YELLOW}Retry %d/%d${C_RESET}\n\n" "$attempt" "$MAX_RETRIES"

    # Check if phase needs planning
    local phase_dir=$(ls -d .planning/phases/$(printf "%02d" "$phase" 2>/dev/null || echo "$phase")-* 2>/dev/null | head -1)

    if [ -z "$phase_dir" ] || [ $(ls "$phase_dir"/*-PLAN.md 2>/dev/null | wc -l) -eq 0 ]; then
      # ── PLANNING ──
      printf "${C_BOLD}Planning${C_RESET}\n"
      echo ""

      start_spinner "Researching domain & patterns..."

      echo "/gsd:plan-phase $phase" | claude -p \
          --allowedTools "Read,Write,Edit,Glob,Grep,Bash,Task,TodoWrite,AskUserQuestion" \
          2>&1 | tee -a "$phase_log"
      local exit_code=${PIPESTATUS[1]}

      if [ $exit_code -ne 0 ]; then
        stop_spinner "error" "Planning failed"
        ((attempt++))
        sleep 5
        continue
      fi

      # Count plans created
      phase_dir=$(ls -d .planning/phases/$(printf "%02d" "$phase" 2>/dev/null || echo "$phase")-* 2>/dev/null | head -1)
      local plan_count=$(ls "$phase_dir"/*-PLAN.md 2>/dev/null | wc -l | tr -d ' ')

      stop_spinner "done" "Created $plan_count plan(s)"
      echo ""
    else
      local plan_count=$(ls "$phase_dir"/*-PLAN.md 2>/dev/null | wc -l | tr -d ' ')
      printf "${C_DIM}Using existing plans: %s${C_RESET}\n\n" "$plan_count"
    fi

    # ── EXECUTION ──
    printf "${C_BOLD}Executing${C_RESET}\n"
    echo ""

    start_spinner "Building features..."

    echo "/gsd:execute-phase $phase" | claude -p \
        --allowedTools "Read,Write,Edit,Glob,Grep,Bash,Task,TodoWrite,AskUserQuestion" \
        2>&1 | tee -a "$phase_log"
    local exit_code=${PIPESTATUS[1]}

    if [ $exit_code -ne 0 ]; then
      stop_spinner "error" "Execution failed"
      ((attempt++))
      sleep 5
      continue
    fi

    stop_spinner "done" "Execution complete"
    echo ""

    # Track cost
    track_cost "$phase_log" "$phase"

    # ── VERIFICATION ──
    printf "${C_BOLD}Verification${C_RESET}\n"
    echo ""

    local verification_file=$(ls "$phase_dir"/*-VERIFICATION.md 2>/dev/null | head -1)
    local status="unknown"

    if [ -f "$verification_file" ]; then
      status=$(grep "^status:" "$verification_file" | head -1 | cut -d: -f2 | tr -d ' ')
    fi

    case "$status" in
      "passed")
        printf "${C_GREEN}✓${C_RESET} Phase verified\n"
        notify "Phase $phase complete" "success"
        return 0
        ;;

      "gaps_found")
        printf "${C_YELLOW}⚠${C_RESET} Gaps found, attempting closure...\n"
        echo ""

        start_spinner "Planning gap closure..."

        echo "/gsd:plan-phase $phase --gaps" | claude -p \
            --allowedTools "Read,Write,Edit,Glob,Grep,Bash,Task,TodoWrite,AskUserQuestion" \
            2>&1 | tee -a "$phase_log"

        if [ ${PIPESTATUS[1]} -ne 0 ]; then
          stop_spinner "error" "Gap planning failed"
          ((attempt++))
          continue
        fi

        stop_spinner "done" "Gap closure planned"

        start_spinner "Executing gap closure..."

        echo "/gsd:execute-phase $phase --gaps-only" | claude -p \
            --allowedTools "Read,Write,Edit,Glob,Grep,Bash,Task,TodoWrite,AskUserQuestion" \
            2>&1 | tee -a "$phase_log"

        if [ ${PIPESTATUS[1]} -ne 0 ]; then
          stop_spinner "error" "Gap execution failed"
          ((attempt++))
          continue
        fi

        track_cost "$phase_log" "$phase"

        # Re-check verification
        status=$(grep "^status:" "$verification_file" 2>/dev/null | tail -1 | cut -d: -f2 | tr -d ' ')

        if [ "$status" = "passed" ]; then
          stop_spinner "done" "Gaps closed, verified"
          notify "Phase $phase complete (after gap closure)" "success"
          return 0
        else
          stop_spinner "error" "Gaps remain"
          ((attempt++))
          continue
        fi
        ;;

      "human_needed")
        printf "${C_CYAN}◆${C_RESET} Human verification needed\n"

        if [ "$CHECKPOINT_MODE" = "queue" ]; then
          queue_checkpoint "$phase" "verification" "{\"type\": \"human_verification\", \"phase\": \"$phase\"}"
          printf "${C_DIM}  Queued for later review${C_RESET}\n"
          return 0
        else
          printf "${C_DIM}  Skipped (checkpoint_mode: skip)${C_RESET}\n"
          return 0
        fi
        ;;

      *)
        printf "${C_DIM}○${C_RESET} No verification required\n"
        return 0
        ;;
    esac
  done

  # All retries exhausted
  echo ""
  printf "${C_RED}${C_BOLD}✗ Phase $phase failed after $MAX_RETRIES attempts${C_RESET}\n"
  notify "Phase $phase FAILED after $MAX_RETRIES attempts" "error"
  return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Execution Loop
# ─────────────────────────────────────────────────────────────────────────────

main() {
  local total_phases=${#PHASES[@]}
  local completed_phases=0
  local start_time=$(date +%s)

  # ── STARTUP BANNER ──
  clear 2>/dev/null || true
  echo ""
  printf "${C_BOLD}${C_CYAN}"
  cat << 'EOF'
   ██████╗ ███████╗██████╗
  ██╔════╝ ██╔════╝██╔══██╗
  ██║  ███╗███████╗██║  ██║
  ██║   ██║╚════██║██║  ██║
  ╚██████╔╝███████║██████╔╝
   ╚═════╝ ╚══════╝╚═════╝
EOF
  printf "${C_RESET}"
  echo ""
  printf "${C_BOLD}${C_WHITE}  AUTOPILOT${C_RESET}\n"
  printf "${C_DIM}  %s${C_RESET}\n" "$PROJECT_NAME"
  echo ""
  printf "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
  echo ""

  # ── CONFIG SUMMARY ──
  printf "${C_DIM}Phases:${C_RESET}     %s\n" "${PHASES[*]}"
  printf "${C_DIM}Retries:${C_RESET}    %s per phase\n" "$MAX_RETRIES"
  printf "${C_DIM}Budget:${C_RESET}     \$%s\n" "$BUDGET_LIMIT"
  printf "${C_DIM}Checkpoints:${C_RESET} %s\n" "$CHECKPOINT_MODE"
  echo ""

  # Overall progress bar
  progress_bar 0 "$total_phases" 40 "Progress"
  echo ""
  echo ""

  notify "Autopilot started for $PROJECT_NAME" "info"

  local remaining_phases=("${PHASES[@]}")

  for phase in "${PHASES[@]}"; do
    # Process any approved checkpoints before starting phase
    process_approved_checkpoints

    # Update remaining list
    remaining_phases=("${remaining_phases[@]:1}")
    local remaining_str="${remaining_phases[*]:-none}"

    update_autopilot_state "running" "$phase" "$remaining_str"

    if ! execute_phase "$phase"; then
      update_autopilot_state "failed" "$phase" "$remaining_str" "phase_$phase_failed"
      echo ""
      printf "${C_RED}${C_BOLD}Autopilot stopped at phase $phase${C_RESET}\n"
      notify "Autopilot STOPPED at phase $phase" "error"
      exit 1
    fi

    # Update progress
    ((completed_phases++))
    echo ""
    progress_bar "$completed_phases" "$total_phases" 40 "Progress"
    echo ""

    # Time estimate
    local elapsed=$(($(date +%s) - start_time))
    local avg_per_phase=$((elapsed / completed_phases))
    local remaining=$((total_phases - completed_phases))
    local eta=$((remaining * avg_per_phase))

    if [ $remaining -gt 0 ]; then
      local eta_min=$((eta / 60))
      local eta_sec=$((eta % 60))
      printf "${C_DIM}~%dm %ds remaining${C_RESET}\n" "$eta_min" "$eta_sec"
    fi
    echo ""
  done

  # Process any final approved checkpoints
  process_approved_checkpoints

  # ── COMPLETION ──
  local total_time=$(($(date +%s) - start_time))
  local total_min=$((total_time / 60))
  local total_sec=$((total_time % 60))

  echo ""
  printf "${C_BOLD}${C_GREEN}"
  cat << 'EOF'
  ╔═══════════════════════════════════════════════════╗
  ║              MILESTONE COMPLETE                   ║
  ╚═══════════════════════════════════════════════════╝
EOF
  printf "${C_RESET}"
  echo ""

  update_autopilot_state "completed" "all" "none"

  # Stats
  printf "${C_WHITE}Phases:${C_RESET}    %d completed\n" "$total_phases"
  printf "${C_WHITE}Time:${C_RESET}      %dm %ds\n" "$total_min" "$total_sec"
  printf "${C_WHITE}Tokens:${C_RESET}    %s\n" "$TOTAL_TOKENS"
  printf "${C_WHITE}Cost:${C_RESET}      \$%s\n" "$TOTAL_COST"
  echo ""

  # Complete milestone
  start_spinner "Finalizing milestone..."

  echo "/gsd:complete-milestone" | claude -p \
    --allowedTools "Read,Write,Edit,Glob,Grep,Bash,AskUserQuestion" \
    2>&1 | tee -a "$LOG_DIR/milestone-complete.log"

  stop_spinner "done" "Milestone finalized"

  notify "Milestone COMPLETE! ${#PHASES[@]} phases, \$$TOTAL_COST" "success"

  # Check for pending checkpoints
  local pending_count=$(ls "$CHECKPOINT_DIR/pending/"*.json 2>/dev/null | wc -l | tr -d ' ')
  if [ "$pending_count" -gt 0 ]; then
    echo ""
    printf "${C_YELLOW}⚠${C_RESET} Pending checkpoints: %d\n" "$pending_count"
    printf "${C_DIM}  Run: /gsd:checkpoints${C_RESET}\n"
  fi

  echo ""
  printf "${C_DIM}Logs: %s/${C_RESET}\n" "$LOG_DIR"
  echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Run
# ─────────────────────────────────────────────────────────────────────────────

main "$@"
