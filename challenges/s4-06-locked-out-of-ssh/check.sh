#!/usr/bin/env bash
# s4-06 — check: a FRESH session connects on the intended port, the firewall
# allows only what it should, and the socket and sshd_config agree.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"
# shellcheck source=lib/assert.sh
. "$LAB_ROOT/lib/assert.sh"

port="${SSH_PORT:-22}"

# A fresh connection, not this session. BatchMode so it cannot block on a
# prompt, and the banner exchange is enough: authentication is not the fault.
# shellcheck disable=SC2016  # the quoted body is not for this shell to expand
assert_cmd "a new SSH connection is accepted on port ${port}" \
  bash -c 'timeout 10 bash -c "exec 3<>/dev/tcp/127.0.0.1/$1 && head -c 20 <&3 | grep -q SSH"' _ "$port"

# Something is actually listening there, and it is sshd's socket.
# shellcheck disable=SC2016  # the body runs in another shell, with its own $1
assert_cmd "something is listening on port ${port}" \
  bash -c 'ss -ltnH "sport = :$1" 2>/dev/null | grep -q .' _ "$port"
assert_cmd "ssh.socket is active" systemctl is-active --quiet ssh.socket

# The two halves agree. This is what a one-sided fix fails.
socket_port="$(systemctl show -p Listen ssh.socket 2>/dev/null \
               | grep -oE '[0-9]+$' | tail -1 || true)"
config_port="$(lab_as_root sshd -T 2>/dev/null | awk '/^port /{print $2}' | head -1 || true)"
if [[ -z "$socket_port" ]]; then
  assert_fail "the socket's listening port can be read" "systemctl show -p Listen ssh.socket"
else
  assert_equal "ssh.socket listens on the configured port" "$socket_port" "$port"
fi
if [[ -z "$config_port" ]]; then
  printf 'SKIP  sshd -T could not be read, so agreement was not checked\n'
else
  assert_equal "sshd_config agrees with the socket (${socket_port} vs ${config_port})" \
    "$config_port" "$socket_port"
fi

# The firewall allows the port that is in use, and nothing surplus.
status="$(lab_as_root ufw status 2>/dev/null || true)"
if grep -qE "^${port}/tcp[[:space:]]+ALLOW" <<<"$status"; then
  assert_pass "ufw allows ${port}/tcp"
else
  assert_fail "ufw allows ${port}/tcp" "sudo ufw allow ${port}/tcp   # or you are locked out again on the next reboot"
fi
if [[ -n "${EXPECTED_PORTS:-}" ]]; then
  extra=""
  while read -r p; do
    [[ -n "$p" ]] || continue
    if [[ " ${EXPECTED_PORTS} " != *" ${p} "* ]]; then extra+="${p} "; fi
  done < <(grep -oE '^[0-9]+' <<<"$status" | sort -un)
  if [[ -z "$extra" ]]; then
    assert_pass "ufw allows nothing outside EXPECTED_PORTS"
  else
    assert_fail "ufw allows nothing outside EXPECTED_PORTS" \
      "also allowed: ${extra}— including the port you moved away from?"
  fi
fi

assert_summary
