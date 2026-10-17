#!/usr/bin/env bash
# svc.sh — service control that reads the same in compose mode and systemd
# mode, so a challenge says "restart the leaves web service" and does not care
# how the lab VM runs it.
#
# Every function takes an app (stages|leaves|nurse|db|nginx) and an optional
# role (web|api). Names and units come from lab.conf, never from here.
set -euo pipefail
# errexit does not reach inside $(...) unless this is set, so a function that
# fails mid-way would otherwise return its partial output with status 0.
shopt -s inherit_errexit

# How a given app is run. RUN_MODE is the default; <APP>_MODE overrides it,
# because the lab does not run all three the same way — leaves starts life as
# gunicorn under systemd precisely so that s6-02 has something to containerise.
svc_mode() {
  local app="${1:-}" var mode
  mode="${RUN_MODE:-}"
  if [[ -n "$app" ]]; then
    var="$(printf '%s_MODE' "${app^^}")"
    mode="${!var:-$mode}"
  fi
  case "$mode" in
    compose|systemd) printf '%s\n' "$mode" ;;
    *) printf 'svc: mode for "%s" must be compose or systemd, got "%s"\n' \
         "${app:-default}" "${mode:-unset}" >&2; return 1 ;;
  esac
}

svc_app_dir() {
  local app="$1" var
  var="$(printf '%s_DIR' "${app^^}")"
  printf '%s\n' "${!var:-}"
}

# The compose service name, or the systemd unit name, for an app and role.
svc_name() {
  local app="${1}" role="${2:-web}" var
  case "$(svc_mode "$app")" in
    compose)
      case "${app}:${role}" in
        stages:web) var=STAGES_WEB ;;  stages:api) var=STAGES_API ;;
        leaves:web) var=LEAVES_WEB ;;  leaves:api) var=LEAVES_API ;;
        nurse:web)  var=NURSE_WEB_SVC ;; nurse:api) var=NURSE_API_SVC ;;
        db:*)       var=DB_SERVICE ;;
        *) printf 'svc: no compose service for %s:%s\n' "$app" "$role" >&2; return 1 ;;
      esac ;;
    systemd)
      case "${app}:${role}" in
        stages:web) var=STAGES_WEB_UNIT ;; stages:api) var=STAGES_API_UNIT ;;
        leaves:web) var=LEAVES_WEB_UNIT ;; leaves:api) var=LEAVES_API_UNIT ;;
        nurse:web)  var=NURSE_WEB_UNIT ;;  nurse:api)  var=NURSE_API_UNIT ;;
        db:*)       var=DB_UNIT ;;
        nginx:*)    var=NGINX_UNIT ;;
        *) printf 'svc: no unit for %s:%s\n' "$app" "$role" >&2; return 1 ;;
      esac ;;
  esac
  printf '%s\n' "${!var:-}"
}

# nginx is always a host unit, in both modes.
svc_compose() {
  local app="$1"; shift
  local dir project var
  dir="$(svc_app_dir "$app")"
  var="$(printf '%s_PROJECT' "${app^^}")"; project="${!var:-$app}"
  [[ -d "$dir" ]] || { printf 'svc: %s is not a directory\n' "$dir" >&2; return 1; }
  ( cd "$dir" && lab_as_root docker compose -p "$project" "$@" )
}

svc_start()   { _svc_do start   "$@"; }
svc_stop()    { _svc_do stop    "$@"; }
svc_restart() { _svc_do restart "$@"; }
svc_enable()  { _svc_do enable  "$@"; }
svc_disable() { _svc_do disable "$@"; }

_svc_do() {
  local action="$1" app="$2" role="${3:-web}" name
  name="$(svc_name "$app" "$role")"
  if [[ "$app" == "nginx" || "$(svc_mode "$app")" == "systemd" ]]; then
    case "$action" in
      start|stop|restart) lab_as_root systemctl "$action" "$name" ;;
      enable)  lab_as_root systemctl enable  --now "$name" ;;
      disable) lab_as_root systemctl disable --now "$name" ;;
    esac
    return
  fi
  case "$action" in
    start)   svc_compose "$app" up -d "$name" ;;
    stop)    svc_compose "$app" stop "$name" ;;
    restart) svc_compose "$app" restart "$name" ;;
    enable)  svc_compose "$app" up -d "$name" ;;   # restart policy, see s3-06
    disable) svc_compose "$app" stop "$name" ;;
  esac
}

svc_is_active() {
  local app="$1" role="${2:-web}" name state
  name="$(svc_name "$app" "$role")"
  if [[ "$app" == "nginx" || "$(svc_mode "$app")" == "systemd" ]]; then
    systemctl is-active --quiet "$name"
    return
  fi
  state="$(svc_compose "$app" ps --status running --format '{{.Service}}' 2>/dev/null || true)"
  grep -qx "$name" <<<"$state"
}

svc_logs() {
  local app="$1" role="${2:-web}" lines="${3:-50}" name
  name="$(svc_name "$app" "$role")"
  if [[ "$app" == "nginx" || "$(svc_mode "$app")" == "systemd" ]]; then
    lab_as_root journalctl -u "$name" -n "$lines" --no-pager
  else
    svc_compose "$app" logs --tail "$lines" "$name"
  fi
}

# Wait for a service to report active. Returns 1 on timeout.
svc_wait_active() {
  local app="$1" role="${2:-web}" timeout="${3:-60}" waited=0
  while (( waited < timeout )); do
    if svc_is_active "$app" "$role"; then return 0; fi
    sleep 2; waited=$(( waited + 2 ))
  done
  return 1
}
