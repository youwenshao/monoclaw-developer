#!/usr/bin/env bash

log_step() {
  printf '\n[%s] %s\n' "$1" "$2"
}

log_ok() {
  printf '  ok: %s\n' "$1"
}

log_warn() {
  printf '  warn: %s\n' "$1"
}

log_action() {
  if [[ "${HATCH_DRY_RUN:-true}" == "true" ]]; then
    printf '  dry-run: %s\n' "$*"
  else
    printf '  run: %s\n' "$*"
    "$@"
  fi
}

have_command() {
  command -v "$1" >/dev/null 2>&1
}

detect_launch_agent() {
  local label="$1"
  launchctl print "gui/$(id -u)/${label}" >/dev/null 2>&1
}
