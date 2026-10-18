#!/usr/bin/env bash
# doctor.sh — diagnose the lab itself.
#
# This is the tool to reach for when a challenge behaves oddly and you cannot
# tell whether the fault is the lab or you. So it has two rules:
#
#   1. It never refuses to run. No lab marker required, no lab.conf required,
#      no sudo required — anything it cannot check becomes a WARN that says why,
#      not an exit.
#   2. It changes nothing. Every command here reads.
#
# Failures print first, then warnings, then what passed. Every failure carries
# the next command to run.
set -euo pipefail
shopt -s inherit_errexit

# Sourced by bin/lab, which provides LAB_ROOT, challenge_ids and kv_get.
DOC_FAIL=(); DOC_WARN=(); DOC_OK=()

if [[ -t 1 ]]; then
  D_RED=$'\033[31m'; D_YEL=$'\033[33m'; D_GRN=$'\033[32m'; D_OFF=$'\033[0m'
else
  D_RED=''; D_YEL=''; D_GRN=''; D_OFF=''
fi

doc_fail() { DOC_FAIL+=("$1"$'\n'"      → $2"); }
doc_warn() { DOC_WARN+=("$1"$'\n'"      → $2"); }
doc_ok()   { DOC_OK+=("$1"); }

# Bounded: a diagnostic that hangs is useless at one in the morning.
doc_run() { timeout 10 "$@" >/dev/null 2>&1; }
doc_out() { timeout 10 "$@" 2>/dev/null || true; }
doc_root() { if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then doc_out "$@"; else doc_out sudo -n "$@"; fi; }
have()    { command -v "$1" >/dev/null 2>&1; }

# --- 1. the marker ----------------------------------------------------------

doc_marker() {
  if [[ ! -f /etc/breakfix-lab ]]; then
    doc_fail "the lab marker is missing — every break.sh will refuse with 97" \
      "echo breakfix-lab | sudo tee /etc/breakfix-lab"
  elif [[ "$(tr -d '[:space:]' < /etc/breakfix-lab)" != "breakfix-lab" ]]; then
    doc_fail "the lab marker exists but its contents are wrong" \
      "cat -A /etc/breakfix-lab   # must read exactly: breakfix-lab\$"
  else
    doc_ok "the lab marker is present and correct"
  fi
  local name
  for name in "${HOSTNAME:-}" "$(hostname 2>/dev/null || true)"; do
    [[ -n "$name" ]] || continue
    case "${name,,}" in
      *prod*|*vps*|*isepsi*)
        doc_fail "the hostname '${name}' contains prod/vps/isepsi, so lab_guard refuses" \
          "sudo hostnamectl set-hostname labvm   # then open a new shell" ;;
    esac
  done
}

# --- 2. lab.conf, and whether its values point at anything real -------------

doc_conf() {
  local key val
  if [[ ! -f "$LAB_ROOT/lab.conf" ]]; then
    doc_fail "no lab.conf — start, check and reset will all refuse" \
      "cp $LAB_ROOT/lab.conf.example $LAB_ROOT/lab.conf  # then edit it"
    return 0
  fi
  doc_ok "lab.conf exists"

  # Keys that must have a value at all.
  for key in RUN_MODE STAGES_DIR STAGES_URL LEAVES_DIR LEAVES_URL LEAVES_PORT \
             NURSE_DIR NURSE_API NURSE_WEB DB_SERVICE BACKUP_DIR \
             LAB_SCRATCH_DIR LAB_SCRATCH_MNT; do
    if [[ -z "${!key:-}" ]]; then
      doc_fail "lab.conf: ${key} is empty" \
        "grep -n '^${key}=' $LAB_ROOT/lab.conf   # compare with lab.conf.example"
    fi
  done

  # Keys a later stage needs, which are empty until someone fills them in.
  #
  # A warning rather than a failure, because the lab works without them right
  # up to the challenge that reads one — and that is the problem being solved
  # here. An unset value surfaces as an assertion failing for a reason that
  # has nothing to do with the fault you were sent to find, so the only useful
  # place to hear about it is before you start. SETUP.md section 10 collects
  # all of these in one pass.
  doc_conf_later() {
    local key="$1" who="$2" how="$3"
    [[ -z "${!key:-}" ]] || { doc_ok "lab.conf: ${key} is set"; return 0; }
    doc_warn "lab.conf: ${key} is empty — needed by ${who}" "$how"
  }
  doc_conf_later LAB_ADMIN_USER "the stage 8 acceptance suite" \
    "id -un   # the account you built this machine with; it checks keys and sudo"
  doc_conf_later EXPECTED_USERS "health_check and lab chaos --check" \
    "awk -F: '\$3>=1000 && \$3<65534 {print \$1}' /etc/passwd | tr '\n' ' '"
  doc_conf_later UPLOADS_PATH "s7-03 and s7-07" \
    "docker volume inspect -f '{{.Mountpoint}}' ${STAGES_UPLOADS_VOLUME:-stages_uploads}"
  doc_conf_later S8_RTO_MINUTES "s8-02" \
    "the recovery time objective in minutes, from your s7-02 report"
  doc_conf_later S8_RUNBOOK_DIR "s8-03" \
    "the Git repository holding your own runbooks — not this one"

  # EXPECTED_PORTS is never empty, which is exactly why it needs checking: the
  # example ships a plausible list, and a list that came from the example
  # asserts only that the example was right.
  if [[ -n "${EXPECTED_PORTS:-}" ]]; then
    listening="$(ss -ltnH 2>/dev/null | awk '{n=split($4,a,":"); print a[n]}' | sort -un | tr '\n' ' ')"
    drift=""
    for port in $listening; do
      [[ " ${EXPECTED_PORTS} " != *" ${port} "* ]] && drift+="+${port} "
    done
    for port in ${EXPECTED_PORTS}; do
      [[ " ${listening} " != *" ${port} "* ]] && drift+="-${port} "
    done
    if [[ -z "$drift" ]]; then
      doc_ok "lab.conf: EXPECTED_PORTS matches what is listening"
    else
      doc_warn "lab.conf: EXPECTED_PORTS does not match what is listening (${drift})" \
        "sudo ss -ltnp   # account for each difference, THEN capture: ss -ltnH | awk '{n=split(\$4,a,\":\"); print a[n]}' | sort -un | tr '\n' ' '"
    fi
  fi

  # Directories that must exist, because challenges cd into them.
  for key in STAGES_DIR LEAVES_DIR NURSE_DIR; do
    val="${!key:-}"
    [[ -n "$val" ]] || continue
    if [[ -d "$val" ]]; then
      doc_ok "${key} points at a real directory (${val})"
    else
      doc_fail "${key}=${val} does not exist" \
        "ls -la $(dirname "$val")   # then SETUP.md section 5, 6 or 7"
    fi
  done

  # Files that challenges read or edit.
  for key in LEAVES_ENV NURSE_ENV NGINX_SITE TLS_CERT TLS_KEY; do
    val="${!key:-}"
    [[ -n "$val" ]] || continue
    if [[ -e "$val" ]]; then
      doc_ok "${key} exists (${val})"
    else
      doc_fail "${key}=${val} does not exist" \
        "sudo ls -la $(dirname "$val")   # the app or nginx section of SETUP.md"
    fi
  done

  # Modes must be one of two words, per app.
  for key in RUN_MODE STAGES_MODE LEAVES_MODE NURSE_MODE; do
    val="${!key:-}"
    [[ -n "$val" ]] || continue
    case "$val" in
      compose|systemd) doc_ok "${key}=${val}" ;;
      *) doc_fail "${key}=${val} is neither compose nor systemd" \
           "sed -i 's|^${key}=.*|${key}=\"systemd\"|' $LAB_ROOT/lab.conf" ;;
    esac
  done

  # The LAN address has to be one this machine actually has.
  if [[ -z "${LAB_LAN_IP:-}" ]]; then
    doc_warn "LAB_LAN_IP is empty — the stage 4 networking challenges need it" \
      "ip -4 addr show scope global | awk '/inet /{print \$2}'   # then set it in lab.conf"
  elif ip -4 addr show scope global 2>/dev/null | grep -q "inet ${LAB_LAN_IP}/"; then
    doc_ok "LAB_LAN_IP=${LAB_LAN_IP} is an address this machine holds"
  else
    doc_fail "LAB_LAN_IP=${LAB_LAN_IP} is not on any interface — it has probably changed" \
      "ip -4 addr show scope global | awk '/inet /{print \$2, \$NF}'   # fix lab.conf AND both /etc/hosts"
  fi

  # The invented hostnames must resolve, on this machine at least.
  local host
  for key in STAGES_VHOST LEAVES_VHOST NURSE_VHOST; do
    host="${!key:-}"
    [[ -n "$host" ]] || continue
    if doc_run getent hosts "$host"; then
      doc_ok "${host} resolves"
    else
      doc_fail "${host} does not resolve on this machine" \
        "printf '%s   %s\\n' \"\${LAB_LAN_IP:-<ip>}\" '$host' | sudo tee -a /etc/hosts"
    fi
  done
}

# --- 3. do the apps answer where lab.conf says they do ----------------------

doc_url() {
  local label="$1" url="$2" hint="$3" code
  [[ -n "$url" ]] || return 0
  code="$(doc_out curl -s -o /dev/null -w '%{http_code}' --max-time 8 "$url")"
  case "$code" in
    200|301|302) doc_ok "${label} answers ${code} at ${url}" ;;
    000|'')      doc_fail "${label} does not answer at all at ${url}" \
                   "curl -v --max-time 5 '${url}' ; ${hint}" ;;
    502|503)     doc_fail "${label} answers ${code} at ${url} — it is proxied but its backend is down" \
                   "${hint}" ;;
    *)           doc_warn "${label} answers ${code} at ${url}, which may be correct for this path" \
                   "curl -v --max-time 5 '${url}'" ;;
  esac
}

doc_apps() {
  doc_url "stages"          "${STAGES_URL:-}" "cd ${STAGES_DIR:-/opt/stages} && docker compose ps && docker compose logs --tail 40 web"
  doc_url "stages api"      "${STAGES_URL:+${STAGES_URL%/}/api/health/}" "cd ${STAGES_DIR:-/opt/stages} && docker compose logs --tail 40 api"
  doc_url "leaves"          "${LEAVES_URL:-}" "systemctl status --no-pager -l leaves ; journalctl -u leaves -n 40 --no-pager"
  doc_url "nurse api"       "${NURSE_API:-}"  "systemctl status --no-pager -l nurse-api ; journalctl -u nurse-api -n 40 --no-pager"
  doc_url "nurse frontend"  "${NURSE_WEB:-}"  "sudo nginx -t ; ls -la ${NURSE_DIR:-/opt/nurse}/frontend/dist/index.html"
  doc_url "nurse list"      "${NURSE_LIST:-}" "journalctl -u nurse-api -n 40 --no-pager"
}

# --- 4. does what is running match what lab.conf claims --------------------

doc_mode() {
  local app mode dir unitvar unit
  for app in stages leaves nurse; do
    local modevar="${app^^}_MODE"
    mode="${!modevar:-${RUN_MODE:-}}"
    dir_var="${app^^}_DIR"; dir="${!dir_var:-}"

    if [[ "$mode" == "compose" ]]; then
      if [[ -n "$dir" ]] && ls "$dir"/compose.y*ml "$dir"/docker-compose.y*ml >/dev/null 2>&1; then
        doc_ok "${app}: mode is compose and a compose file is there"
      else
        doc_fail "${app}: mode is compose but ${dir:-its directory} has no compose file" \
          "ls -la ${dir:-/opt/$app}   # or set ${app^^}_MODE=\"systemd\" in lab.conf"
      fi
      if have docker && doc_run docker info; then
        if [[ -n "$(doc_out docker compose -p "$app" ps -q)" ]]; then
          doc_ok "${app}: containers exist for project '${app}'"
        else
          doc_fail "${app}: no containers for project '${app}'" \
            "cd ${dir:-/opt/$app} && docker compose up -d --wait && docker compose ps"
        fi
      fi
    else
      local seen=""
      for unitvar in "${app^^}_API_UNIT" "${app^^}_WEB_UNIT"; do
        unit="${!unitvar:-}"
        [[ -n "$unit" ]] || continue
        # leaves names one unit for both roles; do not report it twice.
        [[ " $seen " != *" $unit "* ]] || continue
        seen+=" $unit"
        if ! doc_run systemctl cat "$unit"; then
          doc_fail "${app}: mode is systemd but ${unit} does not exist" \
            "ls /etc/systemd/system/${unit}   # SETUP.md section 6 or 7 writes it"
          continue
        fi
        if doc_run systemctl is-active "$unit"; then
          doc_ok "${app}: ${unit} is active"
        else
          doc_fail "${app}: ${unit} exists but is not active" \
            "systemctl status --no-pager -l ${unit} ; journalctl -u ${unit} -n 40 --no-pager"
        fi
        if doc_run systemctl is-enabled "$unit"; then
          doc_ok "${app}: ${unit} is enabled at boot"
        else
          doc_warn "${app}: ${unit} is not enabled — it will not come back after a reboot" \
            "sudo systemctl enable ${unit}   # unless s3-06 is in progress, where this is the fault"
        fi
      done
      # The other half of "matches config": a stack running in the mode we are
      # not in is how a half-finished s6-02 or s6-07 confuses everything after.
      if have docker && doc_run docker info && [[ -n "$(doc_out docker compose -p "$app" ps -q)" ]]; then
        doc_warn "${app}: mode is systemd but containers exist for project '${app}'" \
          "cd ${dir:-/opt/$app} && docker compose ps   # finished s6-02/s6-07? set ${app^^}_MODE=\"compose\""
      fi
    fi
  done

  local u
  for u in "${NGINX_UNIT:-nginx.service}" "${DB_UNIT:-postgresql.service}"; do
    if doc_run systemctl is-active "$u"; then
      doc_ok "${u} is active"
    else
      doc_fail "${u} is not active" \
        "systemctl status --no-pager -l ${u} ; journalctl -u ${u} -n 40 --no-pager"
    fi
  done
  if have nginx || [[ -x /usr/sbin/nginx ]]; then
    if doc_root nginx -t; then doc_ok "the nginx configuration is valid"
    else doc_fail "nginx -t does not pass" "sudo nginx -t   # it names the file and line"; fi
  fi
}

# --- 5. the tools every stage assumes -------------------------------------

doc_tools() {
  local missing=() t
  for t in curl git make jq openssl python3 ss namei runuser sudo \
           losetup mkfs.ext4 findmnt mountpoint fuser lsof pgrep \
           docker shellcheck psql crontab \
           ufw logrotate restic age; do
    have "$t" || missing+=("$t")
  done
  if (( ${#missing[@]} == 0 )); then
    doc_ok "every tool the challenges use is installed"
  else
    doc_fail "missing tools: ${missing[*]}" \
      "sudo apt install -y psmisc lsof e2fsprogs util-linux cron jq shellcheck postgresql-client ufw logrotate restic age"
  fi

  # Needed by one challenge each, and each fails misleadingly without its tool
  # rather than saying what is missing: s4-05 reports an empty hardening
  # baseline, and s4-02's resolution assertion loses its fallback. A warning,
  # because the rest of the lab is unaffected.
  for t in lynis dig; do
    have "$t" && continue
    case "$t" in
      lynis) doc_warn "lynis is not installed — s4-05 cannot score anything" \
               "sudo apt install -y lynis   # without it the check reports an empty baseline, not a missing package" ;;
      dig)   doc_warn "dig is not installed — s4-02 loses its resolution fallback" \
               "sudo apt install -y bind9-dnsutils" ;;
    esac
  done
  if have docker; then
    if doc_run docker info; then
      doc_ok "docker answers as $(id -un) without sudo"
    else
      doc_fail "docker does not answer as $(id -un) — group membership needs a fresh login" \
        "id -nG | tr ' ' '\\n' | grep -x docker || sudo usermod -aG docker $(id -un)   # then log out and in"
    fi
    if doc_run docker compose version; then
      doc_ok "docker compose v2 is available"
    else
      doc_fail "docker compose v2 is missing" "sudo apt install -y docker-compose-plugin"
    fi
  fi
}

# --- 6. loop devices, and somewhere to put the images ---------------------

doc_storage() {
  local root="${LAB_SCRATCH_DIR:-/var/lib/breakfix-lab}" free
  if [[ ! -e /dev/loop-control ]]; then
    doc_fail "no /dev/loop-control — the stage 5 filesystem challenges cannot run" \
      "sudo modprobe loop ; ls -l /dev/loop-control"
  else
    free="$(doc_root losetup -f)"
    if [[ -n "$free" ]]; then
      doc_ok "loop devices are available (next free: ${free})"
    else
      doc_warn "could not read a free loop device (needs root, or all are in use)" \
        "sudo losetup -a   # anything of ours left over from a break?"
    fi
  fi

  if doc_root test -w "$root"; then
    doc_ok "${root} is writable for the loop images"
  elif doc_root test -d "$root"; then
    doc_fail "${root} exists but is not writable even as root" \
      "sudo ls -ld ${root} ; mount | grep -F ${root}"
  else
    doc_warn "${root} does not exist yet — break.sh creates it on first use" \
      "sudo mkdir -p ${root} && sudo ls -ld ${root}"
  fi

  local prog="${HOME}/.breakfix-progress"
  if mkdir -p "$prog" 2>/dev/null && [[ -w "$prog" ]]; then
    doc_ok "${prog} is writable (timers, hints and break state live here)"
  else
    doc_fail "${prog} is not writable — lab cannot record anything" \
      "ls -ld ${HOME} ${prog}"
  fi

  local pct
  pct="$(df -P / 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $5+0}')"
  if [[ -n "$pct" ]] && (( pct >= 85 )); then
    doc_fail "the root filesystem is ${pct}% full — stage 5 needs room to break and recover" \
      "df -h / ; sudo du -xh --max-depth=2 / 2>/dev/null | sort -h | tail -20"
  else
    doc_ok "the root filesystem has room (${pct:-?}% used)"
  fi
}

# --- 7. is the seeded data actually there --------------------------------

doc_seed() {
  local want got
  if [[ -n "${STAGES_URL:-}" ]]; then
    got="$(doc_out curl -fsS --max-time 8 "${STAGES_URL%/}/api/placements/count/")"
    got="${got//[!0-9]/}"
    want="${SEED_PLACEMENTS:-60000}"
    if [[ -z "$got" ]]; then
      doc_warn "could not read the placement count — stages may be down" \
        "curl -v ${STAGES_URL%/}/api/placements/count/"
    elif (( got >= want * 80 / 100 )); then
      doc_ok "stages is seeded (${got} placements, wanted about ${want})"
    elif (( got == 0 )); then
      doc_fail "stages has no placements — nothing is seeded, so s9-07 cannot measure anything" \
        "cd $LAB_ROOT && bash lib/seed.sh stages"
    else
      doc_warn "stages has ${got} placements against ${want} expected" \
        "cd $LAB_ROOT && bash lib/seed.sh stages   # tops up to the target"
    fi
  fi
  if [[ -n "${NURSE_LIST:-}" ]]; then
    got="$(doc_out curl -fsS --max-time 8 "$NURSE_LIST")"
    if [[ -z "$got" ]]; then
      doc_warn "could not read the theses list" "curl -v ${NURSE_LIST}"
    elif grep -qE '"(id|numero)"' <<<"$got"; then
      doc_ok "nurse has records in its list endpoint"
    else
      doc_fail "the theses list is empty — s3-02 cannot distinguish a fault from this" \
        "cd $LAB_ROOT && bash lib/seed.sh nurse"
    fi
  fi
}

# --- 8. anything the lab has left lying around ---------------------------

doc_residue() {
  local id broken n=0 list=""
  for id in $(challenge_ids); do
    broken="$(kv_get "${HOME}/.breakfix-progress/state/${id}/vars" BROKEN_AT 0)"
    [[ "$broken" =~ ^[0-9]+$ ]] || broken=0
    if (( broken > 0 )); then n=$(( n + 1 )); list+="${id} "; fi
  done
  if (( n == 0 )); then
    doc_ok "nothing is recorded as broken"
  else
    doc_warn "${n} challenge(s) are still broken: ${list}" \
      "lab status   # then lab reset <id> for each, or roll back the snapshot"
  fi
  local mounts
  mounts="$(mount 2>/dev/null | grep -c "${LAB_SCRATCH_MNT:-/srv/lab-scratch}" || true)"
  if [[ "${mounts:-0}" -gt 0 ]]; then
    doc_warn "${mounts} lab loop filesystem(s) still mounted" \
      "mount | grep ${LAB_SCRATCH_MNT:-/srv/lab-scratch}   # normal after a reset; lab_fs_destroy removes them"
  fi
}

# --- the command ---------------------------------------------------------

cmd_doctor() {
  doc_marker
  doc_conf
  if [[ -f "$LAB_ROOT/lab.conf" ]]; then
    doc_apps
    doc_mode
    doc_seed
  fi
  doc_tools
  doc_storage
  doc_residue

  local line
  printf '\n'
  if (( ${#DOC_FAIL[@]} > 0 )); then
    for line in "${DOC_FAIL[@]}"; do printf '%sFAIL%s  %s\n' "$D_RED" "$D_OFF" "$line"; done
    printf '\n'
  fi
  if (( ${#DOC_WARN[@]} > 0 )); then
    for line in "${DOC_WARN[@]}"; do printf '%sWARN%s  %s\n' "$D_YEL" "$D_OFF" "$line"; done
    printf '\n'
  fi
  for line in "${DOC_OK[@]}"; do printf '%sok%s    %s\n' "$D_GRN" "$D_OFF" "$line"; done

  printf '\n%d failed, %d warnings, %d ok\n' \
    "${#DOC_FAIL[@]}" "${#DOC_WARN[@]}" "${#DOC_OK[@]}"
  if (( ${#DOC_FAIL[@]} > 0 )); then
    printf 'Fix the failures top-down: the later ones are often caused by the first.\n'
    return 1
  fi
  printf 'The lab looks healthy. If a challenge still behaves oddly, it is the challenge or you.\n'
  printf 'SOLO.md section 1 is how to tell which.\n'
  return 0
}
