#!/usr/bin/env bash
# guard.sh — the lab safety gate, and the state helpers breaks use to be
# reversible.
#
# Source this file and call lab_guard as the FIRST action of any script that
# changes the system. Nothing bypasses lab_guard: every value it tests is
# function-local and literal, so no environment variable, flag or argument can
# move the marker path, rename the marker content, or soften a check.
#
# Refusal exit code is 97. Refusing wrongly is cheap; running wrongly is not.
set -euo pipefail
# errexit does not reach inside $(...) unless this is set, so a function that
# fails mid-way would otherwise return its partial output with status 0.
shopt -s inherit_errexit

# --- the gate ---------------------------------------------------------------

lab_guard_refuse() {
  printf 'lab_guard: REFUSED — %s\n' "$1" >&2
  printf 'lab_guard: this machine does not look like the break-fix lab VM.\n' >&2
  exit 97
}

lab_guard() {
  local marker='/etc/breakfix-lab'
  local expect='breakfix-lab'
  local forbidden_names=('prod' 'vps' 'isepsi')
  local forbidden_mount='/opt/isepsi'
  local content name pattern src tgt

  # Gate one: the lab marker.
  [[ -f "$marker" ]] ||
    lab_guard_refuse "no lab marker file at $marker"
  [[ "$(stat -c '%s' "$marker")" -le 64 ]] ||
    lab_guard_refuse "$marker is too big to be the lab marker"
  content="$(tr -d '[:space:]' <"$marker")"
  [[ "$content" == "$expect" ]] ||
    lab_guard_refuse "$marker does not contain exactly '$expect'"

  # Gate two: identity. Any hostname spelling that looks like the real server.
  for name in "${HOSTNAME:-}" "$(hostname 2>/dev/null || true)" \
              "$(hostname -f 2>/dev/null || true)" \
              "$(cat /etc/hostname 2>/dev/null || true)"; do
    [[ -n "$name" ]] || continue
    name="${name,,}"
    for pattern in "${forbidden_names[@]}"; do
      [[ "$name" != *"$pattern"* ]] ||
        lab_guard_refuse "hostname '$name' contains '$pattern'"
    done
  done

  # Gate two, continued: anything mounted from or onto the real app's tree.
  while read -r src tgt _; do
    [[ -n "${src:-}" ]] || continue
    for pattern in "$src" "${tgt:-}"; do
      [[ "$pattern" != "$forbidden_mount" && "$pattern" != "$forbidden_mount"/* ]] ||
        lab_guard_refuse "a filesystem is mounted at or from $forbidden_mount"
    done
  done </proc/mounts

  return 0
}

# An irreversible break asks for a typed phrase first. Reads the terminal
# directly so a piped stdin cannot answer on the user's behalf.
lab_require_confirm() {
  local phrase="$1" prompt="${2:-This break is not reversible.}" answer=''
  printf '\n%s\n' "$prompt" >&2
  printf "Type exactly '%s' to continue: " "$phrase" >&2
  [[ -r /dev/tty ]] || { printf '\nNo terminal to confirm on; refusing.\n' >&2; exit 98; }
  read -r answer </dev/tty || true
  [[ "$answer" == "$phrase" ]] || { printf 'Not confirmed; nothing was changed.\n' >&2; exit 98; }
}

# Run a privileged command, visibly, without needing sudo when already root.
lab_as_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

# --- state helpers ----------------------------------------------------------
# All lab state lives under $HOME, never in the repo.

lab_state_root() { printf '%s\n' "${HOME}/.breakfix-progress"; }

lab_state_dir() {
  local dir; dir="$(lab_state_root)/state/$1"
  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

lab_state_set() {
  local id="$1" key="$2" value="$3" file
  file="$(lab_state_dir "$id")/vars"
  touch "$file"
  grep -v "^${key}=" "$file" >"${file}.new" 2>/dev/null || true
  printf '%s=%s\n' "$key" "$value" >>"${file}.new"
  mv "${file}.new" "$file"
}

lab_state_get() {
  local id="$1" key="$2" default="${3:-}" file line
  file="$(lab_state_root)/state/${id}/vars"
  [[ -f "$file" ]] || { printf '%s\n' "$default"; return 0; }
  line="$(grep -m1 "^${key}=" "$file" || true)"
  if [[ -n "$line" ]]; then printf '%s\n' "${line#*=}"
  else printf '%s\n' "$default"; fi
}

# Keep one pristine copy of a file before breaking it. Idempotent: a second
# call never overwrites the pristine copy with already-broken content.
lab_backup_file() {
  local id="$1" path="$2" store
  store="$(lab_state_dir "$id")/backup/${path//\//__}"
  mkdir -p "$(dirname "$store")"
  if [[ ! -e "$store" && -e "$path" ]]; then
    lab_as_root cp -a "$path" "$store"
    lab_as_root chown "$(id -u):$(id -g)" "$store"
  fi
}

lab_restore_file() {
  local id="$1" path="$2" store
  store="$(lab_state_root)/state/${id}/backup/${path//\//__}"
  [[ -e "$store" ]] || return 0
  lab_as_root cp -a "$store" "$path"
}
