# Standing rules for this repo

This repo is a **training lab**. It hands out missions and incidents against
three deliberately-deployed web apps on a disposable VM, checks the fixes, and
collects reports. It is not production tooling and nothing here runs anywhere
that matters.

Every contribution, by hand or by model, follows these rules.

## Safety

1. **Every script that changes the system sources `lib/guard.sh` and calls
   `lab_guard` as its first action.** No exceptions, no flag or environment
   variable that skips it. `lab_guard` exits 97.
2. **No real data.** Invented names only. No real student, staff or patient
   records, ever. If a challenge needs data, it seeds its own.
3. **No secrets.** No `.env` files, keys, tokens, passwords, real domains, real
   IP addresses or real hostnames. Example addresses come from RFC 5737
   (`192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`) and `2001:db8::/32`,
   and nothing wider.
4. **No network calls at run time.** `break.sh` and `check.sh` never fetch
   anything. Missions may install packages from the distribution mirrors.
   "Off-VM" is always simulated locally — a second container, a separate mount,
   a second VM — never a real cloud account or a real third-party service.
5. **Every break is reversible** by its own `reset.sh`. Where it genuinely
   cannot be, `meta` carries `RISK=irreversible`, the brief says "snapshot
   required", and `break.sh` makes the user type a confirmation phrase.
6. **Breaks are honest, not sneaky.** A break may hide its cause, but it never
   corrupts data outside its own scope, consumes unbounded disk, leaves an
   unkillable process, or touches SSH access — except in the one challenge
   that is about exactly that, which says so loudly and requires console
   access.
7. **Idempotent.** `break.sh` twice does not deepen the damage. `reset.sh`
   twice is harmless.

## Writing challenges

- **`brief.md` describes symptoms and never causes.** It is a ticket in the
  voice of whoever noticed, with a time and an impact. "The leave app shows a
  502 since about 14:00", not "the gunicorn socket permissions changed".
- **`check.sh` proves the fix, not the symptom.** It asserts the end state —
  the page answers 200, the service survives a restart, the row counts match —
  never merely that a file was edited. One line per assertion, exit 0 or 1.
- **The evidence must be findable** with ordinary tools: `systemctl status`,
  `journalctl`, `docker compose logs`, `ss`, `df`, `ls -l`, `dig`, `curl -v`.
  Never require guessing.
- **`hints.md` is a ladder of four to six lines**: which layer, then which
  tool, then what the tool shows, then the cause, then the fix.
- Nothing hard-codes a path, port or URL. It all comes from `lab.conf`.

## Bash discipline

`#!/usr/bin/env bash` and `set -euo pipefail` at the top, every variable
quoted, `shellcheck` clean with no warnings. `make lint` is the gate.

## Commit messages
Do not add Co-Authored-By, Claude-Session, or "Generated with Claude Code"
trailers to commit messages or PR descriptions.
