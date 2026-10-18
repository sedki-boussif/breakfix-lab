#!/usr/bin/env bash
# s4-03 — break: swap in a certificate that expired weeks ago. Same key, same
# names, only the dates are wrong.
set -euo pipefail
shopt -s inherit_errexit

LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/guard.sh
. "$LAB_ROOT/lib/guard.sh"
lab_guard
# shellcheck source=/dev/null
. "$LAB_ROOT/lab.conf"

ID='s4-03-certificate-warning'
cert="${TLS_CERT:?set TLS_CERT in lab.conf}"
key="${TLS_KEY:?set TLS_KEY in lab.conf}"

[[ -f "$cert" && -f "$key" ]] || {
  printf 'no certificate at %s — SETUP.md section 8 issues it first\n' "$cert" >&2; exit 1; }

lab_backup_file "$ID" "$cert"
lab_backup_file "$ID" "$key"

# A genuinely expired certificate, signed with the existing key so the key
# pairing stays valid and only the dates are wrong.
#
# This uses `openssl ca -selfsign` with -startdate/-enddate rather than
# `req -x509 -not_before/-not_after`: those options do not exist before
# OpenSSL 3.2, and Ubuntu 24.04 ships 3.0.13, where the req form fails
# silently into a certificate that is valid today. Verified on the target.
tmp="$(mktemp -d)"
mkdir -p "$tmp/ca"
: >"$tmp/ca/index.txt"
printf '01\n' >"$tmp/ca/serial"
cat >"$tmp/ca/openssl.cnf" <<CNF
[ca]
default_ca = CA_default
[CA_default]
dir = $tmp/ca
database = \$dir/index.txt
serial = \$dir/serial
new_certs_dir = \$dir
default_md = sha256
policy = policy_any
email_in_dn = no
rand_serial = no
unique_subject = no
copy_extensions = copy
[policy_any]
commonName = supplied
CNF

san="DNS:${STAGES_VHOST:-stages.lab.invalid},DNS:${LEAVES_VHOST:-conge.lab.invalid},DNS:${NURSE_VHOST:-theses.lab.invalid}"
lab_as_root openssl req -new -key "$key" -out "$tmp/req.csr" \
  -subj "/CN=${STAGES_VHOST:-stages.lab.invalid}" \
  -addext "subjectAltName=${san}" >/dev/null 2>&1

if ! lab_as_root openssl ca -config "$tmp/ca/openssl.cnf" -selfsign -keyfile "$key" \
       -in "$tmp/req.csr" -out "$tmp/expired.crt" -batch -notext \
       -startdate "$(date -u -d '400 days ago' +%Y%m%d000000Z)" \
       -enddate   "$(date -u -d '35 days ago'  +%Y%m%d000000Z)" >/dev/null 2>&1; then
  printf 'could not generate a backdated certificate with openssl ca\n' >&2
  rm -rf "$tmp"; exit 1
fi

lab_as_root install -m 644 "$tmp/expired.crt" "$cert"
rm -rf "$tmp"
if lab_as_root nginx -t >/dev/null 2>&1; then
  lab_as_root systemctl reload nginx >/dev/null 2>&1 || true
fi

lab_state_set "$ID" BROKEN_AT "$(date +%s)"
