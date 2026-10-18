#!/usr/bin/env bash
# compose.sh — the standard a containerised lab app is held to, shared by
# s6-02 (leaves) and s6-07 (nurse).
#
# Both missions move an application from gunicorn-under-systemd into a compose
# project, and they are held to the same shape. Keeping that shape in one file
# is the same argument as lib/accept.sh: a standard written twice is two
# standards inside a month, and the second app is where the drift would show.
#
# Everything here reads `docker compose config --format json` through jq rather
# than grepping YAML, because the normalised output is what compose actually
# believes — short-form and long-form syntax, extends, and overrides all come
# out the same way. The one thing read from the raw file instead is secrets:
# `config` resolves variables, so a password from the env file appears in the
# JSON and its absence there would prove nothing.
#
# Needs lab.conf, lib/guard.sh and lib/assert.sh sourced first.
set -euo pipefail
shopt -s inherit_errexit

# compose_json <dir> — the normalised configuration, or empty on failure.
compose_json() {
  ( cd "$1" && lab_as_root docker compose config --format json ) 2>/dev/null || true
}

# compose_q <dir> <jq filter> [args...] — one query against it.
compose_q() {
  local dir="$1" filter="$2"; shift 2
  compose_json "$dir" | jq -r "$filter" "$@" 2>/dev/null || true
}

# compose_shape_assertions <dir> <project> <db service> <app service> <port>
#
# The seven properties both briefs ask for. Each is one assertion and each
# names the fix, because "compose.yaml is wrong" is not a diagnosis.
compose_shape_assertions() {
  local dir="$1" project="$2" db_svc="$3" app_svc="$4" port="$5"
  local json name vols mount missing dep published host_ip raw

  # Every filter below is a jq filter, and jq missing would otherwise abort the
  # check at the first one with "command not found" and no verdict — the same
  # silent-failure shape this repo keeps finding. Say so instead.
  if ! command -v jq >/dev/null 2>&1; then
    assert_fail "jq is installed, which this check reads compose config with" \
      "sudo apt install -y jq   # SETUP.md section 3 installs it; lab doctor checks for it"
    return 0
  fi
  if [[ ! -d "$dir" ]]; then
    assert_fail "the compose project directory exists (${dir})" "nothing there"
    return 0
  fi

  json="$(compose_json "$dir")"
  if [[ -z "$json" ]]; then
    assert_fail "docker compose config validates" \
      "cd ${dir} && sudo docker compose config   # it prints the first error it hits"
    return 0
  fi
  assert_pass "docker compose config validates"

  name="$(jq -r '.name // empty' <<<"$json")"
  assert_equal "the project is named ${project}" "$name" "$project"

  # A named volume, mounted where PostgreSQL actually keeps its data. A bind
  # mount passes a careless check and ties the data to a host path; an
  # anonymous volume survives `down` and is unfindable afterwards.
  mount="$(jq -r --arg s "$db_svc" \
    '.services[$s].volumes // [] | map(select(.target == "/var/lib/postgresql/data")) | .[0] // empty | .type' \
    <<<"$json")"
  case "$mount" in
    volume)
      vols="$(jq -r --arg s "$db_svc" \
        '.services[$s].volumes[] | select(.target == "/var/lib/postgresql/data") | .source' <<<"$json")"
      if jq -e --arg v "$vols" '.volumes | has($v)' <<<"$json" >/dev/null 2>&1; then
        assert_pass "a named volume holds the database's data (${vols})"
      else
        assert_fail "a named volume holds the database's data" \
          "'${vols}' is not declared in the top-level volumes: block, which makes it anonymous — it survives 'down' and you cannot find it again"
      fi ;;
    bind)
      assert_fail "a named volume holds the database's data" \
        "it is a bind mount. That works until the host path moves, and it puts database files where a backup of /opt will half-copy them. Declare a named volume" ;;
    '')
      assert_fail "a named volume holds the database's data" \
        "${db_svc} mounts nothing at /var/lib/postgresql/data, so the data lives in the container's writable layer and 'docker compose down' destroys it" ;;
    *)
      assert_fail "a named volume holds the database's data" "it is a '${mount}' mount" ;;
  esac

  # Healthchecks on everything, because `depends_on` without them only waits
  # for a container to start, and a started PostgreSQL is not a ready one.
  missing="$(jq -r '.services | to_entries | map(select(.value.healthcheck == null or .value.healthcheck.test == null)) | map(.key) | join(" ")' <<<"$json")"
  if [[ -z "$missing" ]]; then
    assert_pass "every service has a healthcheck"
  else
    assert_fail "every service has a healthcheck" \
      "no healthcheck on: ${missing}. Without one, depends_on waits for 'started', and a started database is not a ready one"
  fi

  dep="$(jq -r --arg a "$app_svc" --arg d "$db_svc" \
    '.services[$a].depends_on[$d].condition // empty' <<<"$json")"
  assert_equal "${app_svc} waits for ${db_svc} to be healthy" "$dep" "service_healthy"

  # Published on loopback, on the port the host nginx already proxies to.
  published="$(jq -r --arg a "$app_svc" --arg p "$port" \
    '.services[$a].ports // [] | map(select((.published|tostring) == $p)) | .[0] // empty | .published|tostring' <<<"$json")"
  host_ip="$(jq -r --arg a "$app_svc" --arg p "$port" \
    '.services[$a].ports // [] | map(select((.published|tostring) == $p)) | .[0] // empty | .host_ip // ""' <<<"$json")"
  if [[ -z "$published" ]]; then
    assert_fail "${app_svc} publishes ${port}, the port it always used" \
      "the host nginx proxies to 127.0.0.1:${port} and was not supposed to need changing. Published instead: $(jq -r --arg a "$app_svc" '.services[$a].ports // [] | map(.published|tostring) | join(", ")' <<<"$json")"
  elif [[ "$host_ip" == "127.0.0.1" ]]; then
    assert_pass "${app_svc} publishes 127.0.0.1:${port} only"
  else
    assert_fail "${app_svc} publishes on loopback only" \
      "it publishes ${port} on '${host_ip:-0.0.0.0}', which reaches the network past ufw — Docker writes its own iptables rules, and that is s4-04"
  fi

  # Secrets: read from the RAW file. `config` resolves variables, so a password
  # that came from the env file is present in the JSON either way.
  raw=''
  for cand in "$dir/compose.yaml" "$dir/compose.yml" \
              "$dir/docker-compose.yaml" "$dir/docker-compose.yml"; do
    [[ -f "$cand" ]] && { raw="$cand"; break; }
  done
  if [[ -z "$raw" ]]; then
    assert_fail "there is a compose file to read" "none of compose.yaml, compose.yml, docker-compose.yaml in ${dir}"
  else
    if grep -qE '^\s*(env_file|secrets)\s*:' "$raw"; then
      assert_pass "values come from an env file rather than the compose file"
    else
      assert_fail "values come from an env file rather than the compose file" \
        "no env_file: in ${raw}. compose.yaml is the file that gets committed; the env file is the one that does not"
    fi
    # A literal value after password: or secret_key:, as opposed to a ${VAR}
    # reference. Piping a `grep -q` into another grep — which is what the first
    # version of this did — compares nothing at all: -q prints no output.
    local leaked dollar
    # Built rather than written literally, so shellcheck does not read it as an
    # expansion that forgot its double quotes.
    dollar="$(printf '%s{' '$')"
    leaked="$(grep -niE '(password|secret_key)[a-z_]*:[[:space:]]*["'"'"']?[A-Za-z0-9+/._-]{8,}' "$raw" \
              | grep -Fv "$dollar" || true)"
    if [[ -z "$leaked" ]]; then
      assert_pass "no password is written into the compose file"
    else
      assert_fail "no password is written into the compose file" \
        "$(sed -n 1p <<<"$leaked" | cut -c1-70) — compose.yaml is the file that gets committed"
    fi
  fi
}

# compose_count_rows <dir> <db service> <role> <database> <table>
compose_count_rows() {
  local dir="$1" db_svc="$2" role="$3" db="$4" table="$5"
  [[ "$table" =~ ^[a-z_][a-z0-9_]{0,62}$ ]] || return 0
  ( cd "$dir" && lab_as_root docker compose exec -T "$db_svc" \
      psql -tAq -U "$role" -d "$db" -c "SELECT count(*) FROM \"${table}\"" ) \
    2>/dev/null | tr -d '[:space:]'
}

# compose_survives_destruction <dir> <project> <db service> <role> <database>
#                              <table> <url>
#
# The assertion the whole mission is for. `down` removes the containers and
# leaves the volumes; `down -v` removes the volumes too. Nothing here ever
# passes -v — that difference is the difference between a restart and a data
# loss, and a check that blurred it would be teaching the wrong reflex.
compose_survives_destruction() {
  local dir="$1" project="$2" db_svc="$3" role="$4" db="$5" table="$6" url="$7"
  local before after

  before="$(compose_count_rows "$dir" "$db_svc" "$role" "$db" "$table")"
  if [[ -z "$before" || "$before" == 0 ]]; then
    assert_fail "the data survives the containers being destroyed" \
      "cannot test it: the database reports ${before:-no rows} before the attempt, and a stack that comes back empty from empty is consistent and proves nothing"
    return 0
  fi

  printf 'destroying the containers (down, never down -v)...\n'
  ( cd "$dir" && lab_as_root docker compose down ) >/dev/null 2>&1 || true
  sleep 2
  printf 'bringing them back...\n'
  ( cd "$dir" && lab_as_root docker compose up -d --wait ) >/dev/null 2>&1 || true

  assert_eventually "the project comes back up and answers" 120 \
    curl -fsS -o /dev/null --max-time 5 "$url"

  after="$(compose_count_rows "$dir" "$db_svc" "$role" "$db" "$table")"
  if [[ -z "$after" ]]; then
    assert_fail "the data survives the containers being destroyed" \
      "the database does not answer after coming back — docker compose -p ${project} logs ${db_svc}"
  else
    assert_equal "the data survives the containers being destroyed (${before} rows)" \
      "$after" "$before"
  fi
}
