# Break-fix lab — housekeeping targets.
#
# Recipes use `>` instead of a leading tab (.RECIPEPREFIX) so this file survives
# copy and paste, and .ONESHELL so each recipe is one readable shell script
# rather than a line-continuation puzzle. GNU make 4.x, which is what Ubuntu
# 24.04 has.
.RECIPEPREFIX = >
.ONESHELL:
.DEFAULT_GOAL := help

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
SCRIPTS := bin/lab $(wildcard lib/*.sh) $(wildcard challenges/*/*.sh)

.PHONY: help lint selftest test guard-test

help:
> @echo "make lint       shellcheck every script in the repo"
> echo "make selftest   every challenge complete, well-formed, and how it was verified"
> echo "make guard-test every break.sh refuses with no lab marker (run with it absent)"
> echo "make test       break, prove the check fails, reset, prove it passes"
> echo "                (needs /etc/breakfix-lab and LAB_DISPOSABLE=1)"

lint:
> @command -v shellcheck >/dev/null || {
>   echo "shellcheck is not installed: sudo apt install shellcheck"; exit 1; }
> shellcheck --version | sed -n 2p
> # A UTF-8 locale, or shellcheck dies trying to print a finding on any line
> # containing a dash it did not expect.
> LC_ALL=C.UTF-8 shellcheck -x -P $(CURDIR) $(SCRIPTS)
> echo "shellcheck: clean across $(words $(SCRIPTS)) scripts"
> # The whole repo relies on these three lines being present. Remembering to
> # add them is not a guarantee; failing the build when they are missing is.
> missing=0; n=0
> for f in $(SCRIPTS); do
>   n=$$((n+1))
>   head -1 "$$f" | grep -qx '\#!/usr/bin/env bash' || {
>     echo "  $$f: first line is not #!/usr/bin/env bash"; missing=1; }
>   grep -qx 'set -euo pipefail' "$$f" || {
>     echo "  $$f: missing set -euo pipefail"; missing=1; }
>   grep -qx 'shopt -s inherit_errexit' "$$f" || {
>     echo "  $$f: missing shopt -s inherit_errexit (errexit does not reach inside \$$(...))"; missing=1; }
> done
> (( missing == 0 )) || { echo "shell options: FAILED"; exit 1; }
> echo "shell options: all $$n scripts set the shebang, errexit and inherit_errexit"

selftest:
> @fail=0; n=0; proven=""
> ids="$$(for d in challenges/*/; do basename "$$d"; done)"
> for d in challenges/*/; do
>   id="$$(basename "$$d")"; n=$$((n+1))
>   for f in meta brief.md break.sh check.sh hints.md reset.sh notes.md; do
>     [[ -f "$$d/$$f" ]] || { echo "$$id: missing $$f"; fail=1; }
>   done
>   [[ -f "solutions/$$id.md" ]] || { echo "$$id: no solutions/$$id.md"; fail=1; }
>   lines=$$(grep -cve '^[[:space:]]*$$' "$$d/hints.md" || true)
>   (( lines >= 4 )) || { echo "$$id: only $$lines hints, want at least 4"; fail=1; }
>   (
>     . "$$d/meta"
>     [[ "$$TYPE" == mission || "$$TYPE" == incident ]] || { echo "$$id: bad TYPE=$$TYPE"; exit 1; }
>     [[ "$$LEVEL" =~ ^[1-5]$$ ]] || { echo "$$id: bad LEVEL=$$LEVEL"; exit 1; }
>     [[ "$$SNAPSHOT" == clean || "$$SNAPSHOT" == deployed ]] || { echo "$$id: bad SNAPSHOT=$$SNAPSHOT"; exit 1; }
>     [[ -z "$${RISK:-}" || "$$RISK" == irreversible ]] || { echo "$$id: bad RISK=$$RISK"; exit 1; }
>     case "$${PROVEN:-}" in
>       real|mock-systemd|mock-compose|mock-process|unproven) ;;
>       *) echo "$$id: bad PROVEN=$${PROVEN:-unset}"; exit 1 ;;
>     esac
>     for need in $$NEEDS; do
>       grep -qx "$$need" <<<"$$ids" || { echo "$$id: NEEDS unknown id $$need"; exit 1; }
>     done
>   ) || fail=1
>   proven+="$$(. "$$d/meta"; echo "$$PROVEN $$id")"$$'\n'
> done
> (( fail == 0 )) || exit 1
> opts=0; total=0
> for f in bin/lab lib/*.sh challenges/*/*.sh; do
>   total=$$((total+1))
>   if grep -qx 'set -euo pipefail' "$$f" && grep -qx 'shopt -s inherit_errexit' "$$f"; then
>     opts=$$((opts+1))
>   fi
> done
> echo "selftest: $$n challenges, all well-formed, all with a solution"
> echo "options:  $$opts of $$total scripts set errexit and inherit_errexit"
> echo "verified:"
> cut -d' ' -f1 <<<"$$proven" | grep -v '^$$' | sort | uniq -c | sort -rn \
>   | awk '{printf "  %4d  %s\n", $$1, $$2}'
> stale="$$( { grep '^unproven ' <<<"$$proven" || true; } | cut -d' ' -f2 | tr '\n' ' ')"
> [[ -z "$$stale" ]] && echo "  nothing is unproven" \
>   || echo "  re-verify first on the VM: $$stale"

guard-test:
> @[[ ! -e /etc/breakfix-lab ]] || {
>   echo "refusing: /etc/breakfix-lab exists — this test needs the marker ABSENT"; exit 1; }
> n=0; bad=0
> for s in challenges/*/break.sh; do
>   before="$$(find challenges "$$HOME/.breakfix-progress" -newer "$$s" 2>/dev/null | wc -l)"
>   bash "$$s" >/dev/null 2>&1 && code=0 || code=$$?
>   n=$$((n+1))
>   [[ "$$code" -eq 97 ]] || { bad=$$((bad+1)); echo "  $$s exited $$code, wanted 97"; }
>   after="$$(find challenges "$$HOME/.breakfix-progress" -newer "$$s" 2>/dev/null | wc -l)"
>   [[ "$$before" == "$$after" ]] || { bad=$$((bad+1)); echo "  $$s changed something"; }
> done
> echo "guard-test: $$n break scripts tested, $$((n-bad)) refused with 97 and changed nothing"
> (( bad == 0 ))

test:
> @[[ -f /etc/breakfix-lab ]] || {
>   echo "refusing: no /etc/breakfix-lab, this is not a lab VM"; exit 1; }
> [[ "$${LAB_DISPOSABLE:-}" == 1 ]] || {
>   echo "refusing: set LAB_DISPOSABLE=1 to confirm this VM is disposable"; exit 1; }
> for d in challenges/*/; do
>   id="$$(basename "$$d")"
>   ( . "$$d/meta"
>     [[ "$$TYPE" == incident ]] || exit 9
>     [[ "$${RISK:-}" != irreversible ]] || exit 9 ) || { echo "skip  $$id"; continue; }
>   echo "== $$id"
>   bash "$$d/break.sh"
>   if bash "$$d/check.sh" >/dev/null 2>&1; then
>     echo "  FAIL check passed while broken"; exit 1
>   fi
>   echo "  ok  check fails while broken"
>   bash "$$d/reset.sh"
>   bash "$$d/check.sh" >/dev/null || { echo "  FAIL check still fails after reset"; exit 1; }
>   echo "  ok  check passes after reset"
> done
> echo "test: every reversible incident breaks and resets cleanly"
