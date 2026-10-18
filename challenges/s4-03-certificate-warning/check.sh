#!/usr/bin/env bash
# s4-03 — check: the handshake succeeds for every vhost, the certificate has
# real time left on it, and HTTPS answers. A one-day certificate does not pass.
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

cert="${TLS_CERT:?}"
min_days="${TLS_MIN_DAYS:-14}"

assert_file "the certificate file exists" "$cert"

# Time left, from the file nginx is configured to serve.
if [[ -f "$cert" ]]; then
  end="$(lab_as_root openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2 || true)"
  if [[ -z "$end" ]]; then
    assert_fail "the certificate's expiry can be read" "openssl x509 -in ${cert} -noout -dates"
  else
    left=$(( ( $(date -d "$end" +%s) - $(date +%s) ) / 86400 ))
    assert_above "the certificate has more than ${min_days} days left" "$left" "$min_days" " days"
  fi
fi

# The handshake, per vhost by SNI — so a certificate issued for one name fails.
for host in "${STAGES_VHOST:-stages.lab.invalid}" \
            "${LEAVES_VHOST:-conge.lab.invalid}" \
            "${NURSE_VHOST:-theses.lab.invalid}"; do
  # shellcheck disable=SC2016  # $1 is the inner script's parameter
  assert_cmd "the TLS handshake succeeds for ${host}" \
    bash -c 'openssl s_client -connect 127.0.0.1:443 -servername "$1" </dev/null 2>/dev/null | grep -q "Verify return code\|BEGIN CERTIFICATE"' \
    _ "$host"
  # shellcheck disable=SC2016  # $1 is the inner script's parameter
  assert_cmd "${host} is covered by the certificate's names" \
    bash -c 'openssl s_client -connect 127.0.0.1:443 -servername "$1" </dev/null 2>/dev/null |
             openssl x509 -noout -ext subjectAltName 2>/dev/null | grep -q "$1"' \
    _ "$host"
done

# And it is not expired as far as a client is concerned.
# shellcheck disable=SC2016  # the quoted body is not for this shell to expand
assert_cmd "a client does not reject the certificate on dates" \
  bash -c 'out="$(openssl s_client -connect 127.0.0.1:443 -servername "$1" </dev/null 2>&1)"
           ! grep -qi "certificate has expired\|certificate is not yet valid" <<<"$out"' \
  _ "${LEAVES_VHOST:-conge.lab.invalid}"

assert_cmd "HTTPS answers 200 through the proxy" \
  curl -kfsS -o /dev/null --max-time 10 -H "Host: ${LEAVES_VHOST:-conge.lab.invalid}" \
  "https://127.0.0.1/etoile-formation-conge/"

assert_summary
