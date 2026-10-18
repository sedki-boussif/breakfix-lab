#!/usr/bin/env bash
# accept.sh — the stage 8 acceptance suite: one definition of "this machine is
# finished", shared by all three rebuilds.
#
# Stage 8 contributes almost no new assertions. It runs the ones the earlier
# stages already earned, together, against a machine that was built from
# nothing — because "passed every stage over three weeks" and "passes all of
# them at once, on this boot, on a machine I built this morning" are not the
# same claim, and only the second one is a server.
#
# Where an assertion already exists, this file calls it rather than restating
# it: health_check in lib/assert.sh is the definition of healthy, and is shared
# with `lab chaos --check` so the two can never disagree. What is genuinely new
# here is only this: the port list checked in *both* directions, HTTPS as the
# way in rather than an extra, a restore actually performed and compared, and
# an alert driven through a full fire-and-recover cycle.
#
# Source lab.conf, lib/guard.sh, lib/svc.sh and lib/assert.sh first, then call
# accept_suite. The individual pieces are callable on their own, which is what
# the --arm phases use.
set -euo pipefail
# errexit does not reach inside $(...) unless this is set, so a function that
# fails mid-way would otherwise return its partial output with status 0.
shopt -s inherit_errexit

# accept_url_path <url> — the path part of a lab.conf URL, so the HTTPS checks
# reach each application where it actually lives without a second set of
# variables to drift out of step with the first. Nothing hard-codes a path.
accept_url_path() {
  local rest="${1#*://}"
  case "$rest" in
    */*) printf '%s\n' "/${rest#*/}" ;;
    *)   printf '/\n' ;;
  esac
}

# accept_https — every application answers over TLS, on its own vhost name,
# behind a certificate that covers that name and has time left on it, and plain
# HTTP sends the client to HTTPS rather than serving it.
#
# -k throughout: the lab certificate is self-signed on purpose, so what is
# being tested is the handshake, the names and the proxy, not a public chain.
accept_https() {
  local cert="${TLS_CERT:-}" min_days="${TLS_MIN_DAYS:-14}"
  local end left entry label vhost path code

  if [[ -n "$cert" ]] && lab_as_root test -f "$cert"; then
    end="$(lab_as_root openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2 || true)"
    if [[ -n "$end" ]]; then
      left=$(( ( $(date -d "$end" +%s) - $(date +%s) ) / 86400 ))
      assert_above "the certificate has more than ${min_days} days left" "$left" "$min_days" " days"
    else
      assert_fail "the certificate's expiry can be read" "openssl x509 -in ${cert} -noout -dates"
    fi
  else
    assert_fail "a TLS certificate exists where lab.conf says" \
      "${cert:-TLS_CERT is not set in lab.conf} — SETUP.md section 8 makes it"
  fi

  local -a targets=(
    "stages|${STAGES_VHOST:-}|$(accept_url_path "${STAGES_URL:-}")"
    "leaves|${LEAVES_VHOST:-}|$(accept_url_path "${LEAVES_URL:-}")"
    "the theses API|${NURSE_VHOST:-}|$(accept_url_path "${NURSE_API:-}")"
  )
  [[ -z "${NURSE_WEB:-}" ]] ||
    targets+=("the theses site|${NURSE_VHOST:-}|$(accept_url_path "$NURSE_WEB")")

  # The handshake and the certificate's names are facts about a vhost, not
  # about a URL, and nurse has two URLs behind one name: checking them per
  # target printed the same two assertions twice.
  local seen=''
  for entry in "${targets[@]}"; do
    IFS='|' read -r label vhost path <<<"$entry"
    [[ -n "$vhost" && " $seen " != *" $vhost "* ]] || continue
    seen+=" $vhost"
    # shellcheck disable=SC2016  # $1 is the inner script's parameter, not ours
    assert_cmd "the TLS handshake succeeds for ${vhost}" \
      bash -c 'openssl s_client -connect 127.0.0.1:443 -servername "$1" </dev/null 2>/dev/null |
               grep -q "BEGIN CERTIFICATE"' _ "$vhost"
    # shellcheck disable=SC2016  # $1 is the inner script's parameter, not ours
    assert_cmd "${vhost} is covered by the certificate's names" \
      bash -c 'openssl s_client -connect 127.0.0.1:443 -servername "$1" </dev/null 2>/dev/null |
               openssl x509 -noout -ext subjectAltName 2>/dev/null | grep -q "$1"' _ "$vhost"
  done

  for entry in "${targets[@]}"; do
    IFS='|' read -r label vhost path <<<"$entry"
    if [[ -z "$vhost" ]]; then
      assert_fail "${label} has a vhost name in lab.conf" \
        "set STAGES_VHOST, LEAVES_VHOST and NURSE_VHOST — the names nginx answers on"
      continue
    fi
    assert_cmd "${label} answers over HTTPS (${vhost}${path})" \
      curl -kfsS -o /dev/null --max-time 10 -H "Host: ${vhost}" "https://127.0.0.1${path}"

    # curl carries its own deadline here, which is why this one assertion does
    # not need the library's: --max-time cannot hang.
    code="$(curl -ks -o /dev/null -w '%{http_code}' --max-time 10 \
            -H "Host: ${vhost}" "http://127.0.0.1${path}" 2>/dev/null || true)"
    if [[ "$code" =~ ^30[12378]$ ]]; then
      assert_pass "${label} redirects HTTP to HTTPS (${code})"
    else
      assert_fail "${label} redirects HTTP to HTTPS" \
        "http://${vhost}${path} returned '${code:-no response}' — TLS that is optional is TLS nobody uses"
    fi
  done
}

# accept_ports_exact — the listening set is exactly EXPECTED_PORTS: nothing
# extra, and nothing missing.
#
# health_check only looks for the extra, because a chaos round that took an
# application down is already caught by the application not answering. Here
# both directions matter: a rebuild that forgot a service and a rebuild that
# left a development server running are both unfinished, and the second kind
# passes every other assertion in this file.
accept_ports_exact() {
  local listening extra='' missing='' p

  if [[ -z "${EXPECTED_PORTS:-}" ]]; then
    assert_fail "EXPECTED_PORTS is set in lab.conf" \
      "the suite cannot say the port list is as expected until you have written down what you expect: ss -ltnH | awk '{n=split(\$4,a,\":\"); print a[n]}' | sort -un"
    return 0
  fi

  listening="$(ss -ltnH 2>/dev/null | awk '{n=split($4,a,":"); print a[n]}' | sort -un | tr '\n' ' ')"
  for p in $listening; do
    [[ " ${EXPECTED_PORTS} " != *" ${p} "* ]] && extra+="${p} "
  done
  for p in ${EXPECTED_PORTS}; do
    [[ " ${listening} " != *" ${p} "* ]] && missing+="${p} "
  done

  if [[ -z "$extra" ]]; then
    assert_pass "nothing unexpected is listening"
  else
    assert_fail "nothing unexpected is listening" \
      "extra: ${extra}— sudo ss -ltnp to see what owns them"
  fi
  if [[ -z "$missing" ]]; then
    assert_pass "everything expected is listening (${EXPECTED_PORTS})"
  else
    assert_fail "everything expected is listening" \
      "missing: ${missing}— something in the build did not come back"
  fi
}

# accept_access — the way in, and the way nothing else gets in: the admin
# account with its keys, SSH that only accepts those keys, a firewall that is
# on and narrow, and the container runtime enabled at boot.
accept_access() {
  local user="${LAB_ADMIN_USER:-}" eff status want p extra='' home keys

  if [[ -z "$user" ]]; then
    assert_fail "LAB_ADMIN_USER is set in lab.conf" \
      "name the account you built this machine with; the suite checks its keys and its sudo"
  else
    if getent passwd "$user" >/dev/null 2>&1; then
      assert_pass "the admin account ${user} exists"
      home="$(getent passwd "$user" | cut -d: -f6)"
      keys="${home}/.ssh/authorized_keys"
      if lab_as_root test -s "$keys"; then
        assert_pass "${user} has an authorized_keys with something in it"
      else
        assert_fail "${user} has an authorized_keys with something in it" \
          "${keys} is missing or empty — with password authentication off, that is a machine nobody can log into"
      fi
      if id -nG "$user" 2>/dev/null | tr ' ' '\n' | grep -qx 'sudo'; then
        assert_pass "${user} can escalate (member of sudo)"
      else
        assert_fail "${user} can escalate (member of sudo)" \
          "usermod -aG sudo ${user} — and confirm with: id -nG ${user}"
      fi
    else
      assert_fail "the admin account ${user} exists" "getent passwd ${user} found nothing"
    fi
  fi

  # Asked rather than read: a drop-in under sshd_config.d beats the main file,
  # and only sshd itself knows which won.
  eff="$(lab_as_root sshd -T 2>/dev/null || true)"
  if [[ -z "$eff" ]]; then
    assert_fail "sshd's effective configuration can be read" "sudo sshd -T   # it refuses to print when the config does not parse"
  else
    for want in 'permitrootlogin no' 'passwordauthentication no' 'pubkeyauthentication yes'; do
      if grep -qx "$want" <<<"$eff"; then
        assert_pass "sshd will actually do: ${want}"
      else
        assert_fail "sshd will actually do: ${want}" \
          "sudo sshd -T | grep ${want%% *}   # and check /etc/ssh/sshd_config.d/ for an override"
      fi
    done
  fi
  assert_cmd "ssh is enabled at boot" \
    bash -c 'systemctl is-enabled --quiet ssh.service || systemctl is-enabled --quiet ssh.socket'

  status="$(lab_as_root ufw status verbose 2>/dev/null || true)"
  if grep -qE 'Status:[[:space:]]*active' <<<"$status"; then
    assert_pass "ufw is active"
  else
    assert_fail "ufw is active" "sudo ufw status verbose — a built server with the firewall off is not built"
  fi
  if grep -qE 'Default:.*deny \(incoming\)' <<<"$status"; then
    assert_pass "the default inbound policy is deny"
  else
    assert_fail "the default inbound policy is deny" "sudo ufw default deny incoming"
  fi
  if [[ -n "${EXPECTED_PORTS:-}" ]]; then
    while read -r p; do
      [[ -n "$p" ]] || continue
      [[ " ${EXPECTED_PORTS} " != *" ${p} "* ]] && extra+="${p} "
    done < <(grep -oE '^[0-9]+' <<<"$status" | sort -un)
    if [[ -z "$extra" ]]; then
      assert_pass "ufw allows only expected ports"
    else
      assert_fail "ufw allows only expected ports" "also allowed: ${extra}"
    fi
  fi

  assert_cmd "docker is running" systemctl is-active --quiet docker
  assert_cmd "docker is enabled at boot" systemctl is-enabled --quiet docker
}

# accept_stages_count <database> — placements in one stages database. Used to
# compare a restored fingerprint against what is actually being served.
accept_stages_count() {
  ( cd "${STAGES_DIR:?}" && lab_as_root docker compose exec -T "${DB_SERVICE:-db}" \
      psql -tAq -U "${POSTGRES_USER:-stages_owner}" -d "$1" \
      -c 'SELECT count(*) FROM placements' ) 2>/dev/null | tr -d '[:space:]'
}

# accept_backup_restored — a backup has run, and the archive restores to the
# data this machine is actually serving.
#
# The suite performs the restore itself rather than taking the word of a
# previous drill. It restores only the fingerprint file, which is small and
# bounded, and then compares it against a live row count: that proves the
# repository is readable, that the latest snapshot has real content in it, and
# that the content agrees with what is being served. An archive nobody has read
# back is a directory, and "the backup job exits 0" is not the claim.
#
# A consequence worth knowing before you are surprised by it: this compares the
# *latest* snapshot against *now*, so seed the data first and back it up last.
# Row counts that have moved since the archive was written are a real
# difference, and the suite is right to say so.
accept_backup_restored() {
  local repo="${BACKUP_REMOTE:-}" pw="${BACKUP_PASSWORD_FILE:-}" fp="${BACKUP_FINGERPRINT:-}"
  local target="${S8_RESTORE_TARGET:-/var/tmp/s8-restore}"
  local restored want live

  if [[ -z "$repo" || -z "$pw" || -z "$fp" ]]; then
    assert_fail "the backup repository is configured in lab.conf" \
      "BACKUP_REMOTE, BACKUP_PASSWORD_FILE and BACKUP_FINGERPRINT must all be set — s7-01 builds them"
    return 0
  fi

  assert_cmd "the off-site repository holds at least one snapshot" \
    lab_as_root restic -r "$repo" --password-file "$pw" snapshots --json

  lab_as_root rm -rf "$target" 2>/dev/null || true
  assert_cmd "the latest snapshot restores" \
    lab_as_root restic -r "$repo" --password-file "$pw" restore latest \
    --target "$target" --include "$fp"

  restored="${target}${fp}"
  if ! lab_as_root test -s "$restored"; then
    assert_fail "the restored archive contains the fingerprint" \
      "${fp} was not in the latest snapshot — a backup that does not include the fingerprint cannot be verified after a restore"
    return 0
  fi
  assert_pass "the restored archive contains the fingerprint"

  want="$(lab_as_root sed -n 's/^placements=//p' "$restored" 2>/dev/null | tr -d '[:space:]')"
  if [[ -z "$want" ]]; then
    assert_fail "the restored fingerprint records a row count" \
      "write row counts into ${fp} at backup time: s7-01's standard, item 6"
    return 0
  fi
  live="$(accept_stages_count "${POSTGRES_DB:-stages}")"
  if [[ -z "$live" ]]; then
    assert_fail "the live row count can be read to compare against" \
      "the stages database did not answer — docker compose ps in ${STAGES_DIR:-/opt/stages}"
  else
    assert_equal "the restored data matches what is being served (${want} placements)" "$live" "$want"
  fi
}

# accept_fingerprint_matches_live — every row count the archive recorded, against
# the database now serving.
#
# accept_backup_restored compares one table, which is enough to prove a restore
# happened. This compares all of them, which is the stronger claim s8-02 needs:
# after a rebuild from backups alone, the data being served has no other source,
# so a count that disagrees anywhere means the recovery lost something. A
# restore that returns the wrong data quietly is the failure mode worth more
# than the one where it returns nothing.
#
# The fingerprint is "table=count" per line, s7-01's format. Lines naming a
# table the stages database does not have are reported rather than failed —
# a fingerprint may legitimately cover more than one application — but at least
# one line has to have been comparable, or nothing was checked.
accept_fingerprint_matches_live() {
  local restored="$1" compared=0 table want live

  if ! lab_as_root test -s "$restored"; then
    assert_fail "the archive's fingerprint can be read" "${restored} is missing or empty"
    return 0
  fi

  while IFS='=' read -r table want; do
    [[ "$table" =~ ^[a-z_][a-z0-9_]*$ ]] || continue
    [[ "$want" =~ ^[0-9]+$ ]] || continue
    live="$(accept_stages_count_table "$table")"
    if [[ -z "$live" ]]; then
      printf 'SKIP  %s is in the fingerprint but not in the stages database\n' "$table"
      continue
    fi
    compared=$(( compared + 1 ))
    assert_equal "restored ${table} matches the archive (${want})" "$live" "$want"
  done < <(lab_as_root cat "$restored" 2>/dev/null || true)

  if (( compared == 0 )); then
    assert_fail "at least one row count was comparable" \
      "nothing in ${restored} named a table that could be counted, so 'the data matches' was never tested"
  else
    assert_pass "${compared} row count(s) in the archive were checked against live data"
  fi
}

# accept_stages_count_table <table> — rows in one stages table, or empty when
# the table is not there. Separate from accept_stages_count because that one is
# deliberately fixed on placements, and a table name reaching psql has to be
# checked against the catalogue before it is interpolated.
accept_stages_count_table() {
  local table="$1" exists
  # A table name is about to be interpolated into SQL, so it is checked against
  # this pattern and then against the catalogue before it is used as an
  # identifier. Nothing here takes a name from anywhere but the fingerprint
  # file the backup wrote, but "the input happened to be trustworthy" is not
  # the same as validating it.
  [[ "$table" =~ ^[a-z_][a-z0-9_]{0,62}$ ]] || return 0

  # Existence first, as its own query: asking for the count of a table that is
  # not there and asking for the count of an empty table both answer "0" if
  # the two questions are run together, and those are different answers.
  exists="$(accept_stages_psql \
    "SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = '${table}'")"
  [[ "$exists" == 1 ]] || return 0

  accept_stages_psql "SELECT count(*) FROM \"${table}\""
}

# accept_stages_psql <sql> — one query against the live stages database.
accept_stages_psql() {
  ( cd "${STAGES_DIR:?}" && lab_as_root docker compose exec -T "${DB_SERVICE:-db}" \
      psql -tAq -U "${POSTGRES_USER:-stages_owner}" -d "${POSTGRES_DB:-stages}" \
      -c "$1" ) 2>/dev/null | tr -d '[:space:]'
}

# accept_alert_cycle — one alert fires, and then recovers.
#
# Both halves are driven, not observed: the suite makes the backups look stale,
# requires an alert, puts the marker back, and requires the alerting to go
# quiet. Monitoring is tested by making it speak; a quiet alert log proves
# nothing on its own, and a channel that never clears gets filtered within a
# week, which is the same as having no monitoring with extra steps.
#
# The second half is an absence claim, and its positive control is the first
# half: the same marker, the same watcher, the same log, a moment earlier. The
# control is planted in the real subject's own domain, which is the condition
# that makes one worth anything.
accept_alert_cycle() {
  local marker="${BACKUP_MARKER:-}" alog="${BACKUP_ALERT_LOG:-}"
  local timer="${BACKUP_TIMER:-}" watch="${BACKUP_WATCH_SERVICE:-lab-backup-watch.service}"
  local mtime before after waited

  if [[ -z "$marker" || -z "$alog" || -z "$timer" ]]; then
    assert_fail "the backup alerting is configured in lab.conf" \
      "BACKUP_MARKER, BACKUP_ALERT_LOG and BACKUP_TIMER must all be set — s7-01 builds them"
    return 0
  fi

  # The marker's mtime is the only thing being changed, and it has to come back
  # whatever happens below. If it cannot be read, nothing is touched at all:
  # backdating a marker this function then cannot restore would leave the
  # machine looking as though its backups had stopped.
  mtime="$(lab_as_root stat -c '%Y' "$marker" 2>/dev/null || true)"
  if [[ -z "$mtime" ]]; then
    assert_fail "an alert fires when the backups go stale" \
      "${marker} does not exist, so there is nothing to make stale — s7-01 builds it"
    return 0
  fi

  before="$(lab_as_root wc -l <"$alog" 2>/dev/null || echo 0)"
  lab_as_root systemctl stop "$timer" >/dev/null 2>&1 || true
  lab_as_root touch -d '5 days ago' "$marker" 2>/dev/null || true
  lab_as_root systemctl start "$watch" >/dev/null 2>&1 || true

  after="$before"; waited=0
  while (( waited < 30 )); do
    after="$(lab_as_root wc -l <"$alog" 2>/dev/null || echo 0)"
    if (( after > before )); then break; fi
    sleep 3; waited=$(( waited + 3 ))
  done
  if (( after > before )); then
    assert_pass "an alert fires when the backups go stale (after ${waited}s)"
  else
    assert_fail "an alert fires when the backups go stale" \
      "nothing was appended to ${alog} in ${waited}s. A backup system with no dead-man's-switch says nothing on the day it stops"
  fi

  # Put it back, then require the alerting to agree that it is back.
  lab_as_root touch -d "@${mtime}" "$marker" 2>/dev/null || true
  lab_as_root systemctl start "$timer" >/dev/null 2>&1 || true
  before="$(lab_as_root wc -l <"$alog" 2>/dev/null || echo 0)"
  lab_as_root systemctl start "$watch" >/dev/null 2>&1 || true
  sleep 10
  after="$(lab_as_root wc -l <"$alog" 2>/dev/null || echo 0)"
  if (( after == before )); then
    assert_pass "and it goes quiet once the backups are healthy again"
  else
    assert_fail "and it goes quiet once the backups are healthy again" \
      "${alog} is still growing with a fresh marker — an alert that never clears is an alert nobody reads"
  fi

  assert_cmd "the backup timer is running again after the drill" \
    systemctl is-active --quiet "$timer"
  health_file_fresh "the backup marker is fresh again" "$marker" "${BACKUP_MAX_AGE_H:-30}"
}

# accept_rebooted <arm file> — this machine has booted since the suite was
# armed. A rebuild that has never been rebooted is a rebuild nobody has tested:
# every service enabled by hand works until the machine stops, and s3-06 is the
# whole lesson. The only honest test of "it comes back" is that it came back.
accept_rebooted() {
  local armfile="$1" boot_id
  boot_id="$(cat /proc/sys/kernel/random/boot_id)"
  if [[ ! -s "$armfile" ]]; then
    assert_fail "the suite was armed before the reboot" \
      "check.sh --arm records the boot id this is compared against"
  elif [[ "$(cat "$armfile")" == "$boot_id" ]]; then
    assert_fail "the machine has rebooted since arming" \
      "the boot id has not changed — reboot it, then run the check again"
  else
    assert_pass "the machine has rebooted since arming"
  fi
}

# accept_report_time <report> <what> — the elapsed time is written down.
#
# Not a formality. A rebuild time nobody recorded cannot be improved on, and
# the number is only knowable by the person who did it, which is why the suite
# asks the report for it rather than measuring something it cannot see.
accept_report_time() {
  local report="$1" what="$2"
  if [[ ! -f "$report" ]]; then
    assert_fail "the report exists" "lab report $(basename "${report%.md}")   # the time is the point of this one"
    return 0
  fi
  if grep -qiE '([0-9]+ *(m|min|minute|minutes|h|hr|hour|hours))|[0-9]+:[0-9]{2}' "$report"; then
    assert_pass "the report records ${what}"
  else
    assert_fail "the report records ${what}" \
      "put the elapsed time in ${report} — a number you did not write down becomes a guess, and under pressure a guess becomes a promise"
  fi
}

# accept_suite — everything above, in the order a person would check it.
#
# The section headers are the one place in the lab where a check prints
# something that is not an assertion. Sixty consecutive PASS lines are not
# readable, and the headers survive grep for PASS or FAIL unchanged.
accept_suite() {
  printf '\n-- healthy, by the same definition lab chaos --check uses ---------\n'
  health_check
  printf '\n-- every application answers over HTTPS ---------------------------\n'
  accept_https
  printf '\n-- the listening set is exactly what was expected -----------------\n'
  accept_ports_exact
  printf '\n-- the way in, and the firewall around it -------------------------\n'
  accept_access
  printf '\n-- a backup has run, and restores to the right data --------------\n'
  accept_backup_restored
  printf '\n-- an alert fires, and recovers ----------------------------------\n'
  accept_alert_cycle
  printf '\n'
}
