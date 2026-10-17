# s0-00-smoke — author notes

**This challenge is throwaway.** It exists to prove the `lab` loop end to end
(list, start, hint, check, report, reset) before any of the three apps are
deployed, and it is deleted once Stage 3 has a real service incident. Nothing
else should ever depend on it.

**What the fault really is.** The wrapper that starts the status page is
rewritten to `exec` an interpreter that does not exist (`python3-lab`). The
process dies instantly, so the port is closed and the page times out. The
evidence chain is ordinary: `ss -ltnp` shows nothing on the port, the wrapper's
log shows the failed exec, the wrapper shows the wrong path.

**Why it is deliberately unlike the rest of the catalogue.** It does not use
systemd or Docker, and needs no root. The service is a plain background process
under `~/.breakfix-progress/state/s0-00-smoke/service/`, so the whole loop can
be exercised on a bare VM, or in a container, before `SETUP.md` exists. That
also means it does **not** exercise `lib/svc.sh` — the first challenge to do
that is s3-01.

**Realism.** Low, by design. A broken `ExecStart` path is the real version of
this fault and it is s3-01's job; this is the same shape with no dependencies.
