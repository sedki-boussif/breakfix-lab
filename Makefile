# Break-fix lab — housekeeping targets.
#
# Recipes use `>` instead of a leading tab (.RECIPEPREFIX), so this file
# survives copy and paste. GNU make 4.x only, which is what Ubuntu 24.04 has.
.RECIPEPREFIX = >
.DEFAULT_GOAL := help

SHELL := /usr/bin/env bash
SCRIPTS := bin/lab $(wildcard lib/*.sh) $(wildcard challenges/*/*.sh)

.PHONY: help lint test selftest

help:
> @echo "make lint      shellcheck every script in the repo"
> @echo "make selftest  check every challenge is complete and well-formed"
> @echo "make test      break, prove the check fails, reset, prove it passes"
> @echo "               (needs /etc/breakfix-lab and LAB_DISPOSABLE=1)"

lint:
> @command -v shellcheck >/dev/null || { \
>   echo "shellcheck is not installed: sudo apt install shellcheck"; exit 1; }
> @shellcheck --version | sed -n 2p
> shellcheck -x -P $(CURDIR) $(SCRIPTS)
> @echo "shellcheck: clean across $(words $(SCRIPTS)) scripts"

selftest:
> @bash -c 'set -euo pipefail; \
>   fail=0; n=0; \
>   ids=$$(for d in challenges/*/; do basename "$$d"; done); \
>   for d in challenges/*/; do \
>     id=$$(basename "$$d"); n=$$((n+1)); \
>     for f in meta brief.md break.sh check.sh hints.md reset.sh notes.md; do \
>       [[ -f "$$d/$$f" ]] || { echo "$$id: missing $$f"; fail=1; }; \
>     done; \
>     ( . "$$d/meta"; \
>       [[ "$$TYPE" == mission || "$$TYPE" == incident ]] || { echo "$$id: bad TYPE=$$TYPE"; exit 1; }; \
>       [[ "$$LEVEL" =~ ^[1-5]$$ ]] || { echo "$$id: bad LEVEL=$$LEVEL"; exit 1; }; \
>       [[ "$$SNAPSHOT" == clean || "$$SNAPSHOT" == deployed ]] || { echo "$$id: bad SNAPSHOT=$$SNAPSHOT"; exit 1; }; \
>       [[ -z "$${RISK:-}" || "$$RISK" == irreversible ]] || { echo "$$id: bad RISK=$$RISK"; exit 1; }; \
>       for need in $$NEEDS; do \
>         grep -qx "$$need" <<<"$$ids" || { echo "$$id: NEEDS unknown id $$need"; exit 1; }; \
>       done ) || fail=1; \
>     lines=$$(grep -cve "^[[:space:]]*$$" "$$d/hints.md" || true); \
>     (( lines >= 4 )) || { echo "$$id: only $$lines hints, want at least 4"; fail=1; }; \
>   done; \
>   (( fail == 0 )) && echo "selftest: $$n challenges, all well-formed" || exit 1'

test:
> @bash -c 'set -euo pipefail; \
>   [[ -f /etc/breakfix-lab ]] || { echo "refusing: no /etc/breakfix-lab, this is not a lab VM"; exit 1; }; \
>   [[ "$${LAB_DISPOSABLE:-}" == 1 ]] || { echo "refusing: set LAB_DISPOSABLE=1 to confirm this VM is disposable"; exit 1; }; \
>   for d in challenges/*/; do \
>     id=$$(basename "$$d"); \
>     ( . "$$d/meta"; [[ "$$TYPE" == incident ]] || exit 9; [[ "$${RISK:-}" != irreversible ]] || exit 9 ) || { echo "skip  $$id"; continue; }; \
>     echo "== $$id"; \
>     bash "$$d/break.sh"; \
>     if bash "$$d/check.sh" >/dev/null 2>&1; then echo "  FAIL check passed while broken"; exit 1; fi; \
>     echo "  ok  check fails while broken"; \
>     bash "$$d/reset.sh"; \
>     bash "$$d/check.sh" >/dev/null || { echo "  FAIL check still fails after reset"; exit 1; }; \
>     echo "  ok  check passes after reset"; \
>   done; \
>   echo "test: every reversible incident breaks and resets cleanly"'
