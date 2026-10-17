#!/usr/bin/env bash
# chaos.sh — `lab chaos`: a fault you did not choose, at a time you did not pick.
#
# Everything else in this lab tells you which challenge you are doing. This
# does not, and that is the entire point: knowing something is broken, knowing
# it is broken all the time, and knowing there is exactly one thing wrong are
# three assumptions production does not grant you.
#
# Sourced by bin/lab, which provides LAB_ROOT, challenge_ids, kv_get, the
# colour variables and die.
set -euo pipefail
shopt -s inherit_errexit

chaos_dir()   { local d="${HOME}/.breakfix-progress/chaos"; mkdir -p "$d"; printf '%s\n' "$d"; }
chaos_latest() {
  local d; d="$(chaos_dir)"
  find "$d" -maxdepth 1 -name 'round-*' -type f 2>/dev/null | sort | tail -1
}

# The pool: reversible incidents at level 2 to 4. Anything that needs a
# snapshot, a console, or a reboot to undo is excluded by RISK, because a chaos
# round is supposed to be survivable without planning.
chaos_pool() {
  local id path
  for id in $(challenge_ids); do
    path="$CHALLENGE_DIR/$id"
    (
      # shellcheck source=/dev/null
      . "$path/meta"
      [[ "$TYPE" == incident ]]            || exit 1
      [[ "${RISK:-}" != irreversible ]]    || exit 1
      [[ "$LEVEL" =~ ^[234]$ ]]            || exit 1
      [[ "$STAGE" != 0 ]]                  || exit 1
    ) || continue
    # Not one that is already broken.
    [[ "$(kv_get "${HOME}/.breakfix-progress/state/${id}/vars" BROKEN_AT 0)" == 0 ]] || continue
    printf '%s\n' "$id"
  done
}

cmd_chaos() {
  case "${1:-}" in
    --check)    chaos_check ;;
    --reveal)   chaos_reveal ;;
    --pool)     chaos_pool ;;
    ''|--fire)  chaos_fire ;;
    *)          die "usage: lab chaos [--check | --reveal | --pool]" ;;
  esac
}

chaos_fire() {
  load_conf
  local pool=() roll n=0 id round file picked=()
  mapfile -t pool < <(chaos_pool)
  if (( ${#pool[@]} == 0 )); then
    die "nothing eligible to fire: every reversible level 2-4 incident is already broken or passed-over. Try: lab status"
  fi

  # 65% one fault, 20% two, 15% nothing at all.
  #
  # Seeded from urandom first: bash seeds RANDOM from the time and the pid, so
  # rounds fired within the same second or two correlate, which showed up in
  # testing as far too many empty rounds in a row.
  RANDOM=$(( $(od -An -N2 -tu2 </dev/urandom | tr -d ' ') ))
  roll=$(( RANDOM % 100 ))
  if   (( roll < 65 )); then n=1
  elif (( roll < 85 )); then n=2
  else                       n=0
  fi
  (( n <= ${#pool[@]} )) || n=${#pool[@]}

  round="$(date +%Y%m%d-%H%M%S)"
  file="$(chaos_dir)/round-${round}"

  # Shuffle the pool, take n.
  mapfile -t pool < <(printf '%s\n' "${pool[@]}" | shuf)
  local i
  for (( i = 0; i < n; i++ )); do picked+=("${pool[$i]}"); done

  for id in ${picked[@]+"${picked[@]}"}; do
    LAB_ID="$id" bash "$CHALLENGE_DIR/$id/break.sh" >/dev/null 2>&1 || true
  done

  # The truth, in a form you will not read by accident. base64 is not a secret,
  # it is a speed bump: this is a discipline aid, not a security boundary.
  {
    printf 'round=%s\n' "$round"
    printf 'fired=%d\n' "$n"
    printf 'ids=%s\n' "${picked[*]-}"
  } | base64 -w0 >"$file"
  # base64 -w0 emits no trailing newline, so the marker needs one of its own or
  # it lands on the end of the encoded line and nothing decodes.
  printf '\nrevealed=0\n' >>"$file"

  printf '\n%s   round %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$round"
  printf 'Something may have happened. Find out what, if anything.\n\n'
  printf '  lab chaos --check     assert the machine is healthy\n'
  printf '  lab chaos --reveal    give up, and mark the round revealed\n\n'
  printf 'Write a report either way, including if you conclude nothing is wrong.\n'
}

chaos_check() {
  load_conf
  # shellcheck source=lib/svc.sh
  . "$LAB_ROOT/lib/svc.sh"
  # shellcheck source=lib/assert.sh
  . "$LAB_ROOT/lib/assert.sh"

  local file round
  file="$(chaos_latest)"
  if [[ -n "$file" ]]; then
    round="$(basename "$file")"; round="${round#round-}"
    printf '\n%sround %s%s — asserting health, not a particular fault\n\n' \
      "$C_TITLE" "$round" "$C_OFF"
  else
    printf '\n%sno chaos round recorded%s — asserting health anyway\n\n' "$C_TITLE" "$C_OFF"
  fi

  health_check
  local status=0
  assert_summary || status=$?

  if (( status == 0 )); then
    printf '\n%sHEALTHY%s\n' "$C_PASS" "$C_OFF"
    printf 'If this round fired nothing, that is the pass: you proved health rather\n'
    printf 'than finding a fault, which is the harder half of the job.\n'
  else
    printf '\n%sNOT HEALTHY%s — the failures above are where to start.\n' "$C_FAIL" "$C_OFF"
    printf 'They name the symptom, not the cause. lab doctor tells you whether the\n'
    printf 'lab itself is sound before you go looking.\n'
  fi
  printf '\nEither way, write the report — including if you conclude nothing is wrong:\n'
  printf '  cp %s/report-template.md %s/reports/chaos-%s.md\n' \
    "$LAB_ROOT" "$LAB_ROOT" "${round:-$(date +%Y%m%d)}"
  return "$status"
}

chaos_reveal() {
  local file round decoded
  file="$(chaos_latest)"
  [[ -n "$file" ]] || die "no chaos round has been fired yet"
  round="$(basename "$file")"; round="${round#round-}"

  decoded="$(head -1 "$file" | base64 -d 2>/dev/null || true)"
  [[ -n "$decoded" ]] || die "round ${round} is unreadable — the file is $file"

  local fired ids
  fired="$(sed -n 's/^fired=//p' <<<"$decoded")"
  ids="$(sed -n 's/^ids=//p' <<<"$decoded")"

  printf '\nround %s\n' "$round"
  if [[ "${fired:-0}" == 0 ]]; then
    printf 'Nothing fired. The machine was healthy all along.\n'
    printf 'If you found a fault anyway, it was real and it was not me.\n'
  else
    printf 'Fired %s:\n' "$fired"
    local id
    for id in $ids; do
      printf '  %-32s %s\n' "$id" "$(sed -n 's/^TITLE=//p' "$CHALLENGE_DIR/$id/meta" | tr -d '"')"
    done
    printf '\nTo put them back:\n'
    for id in $ids; do printf '  lab reset %s\n' "$id"; done
    printf '\nThe notes say what each fault really was:\n'
    for id in $ids; do printf '  cat challenges/%s/notes.md\n' "$id"; done
  fi
  sed -i 's/^revealed=0$/revealed=1/' "$file"
  printf '\nRound %s marked revealed.\n' "$round"
}
