# s3-02 — author notes

**What the fault really is.** `DATABASE_URL` in the nurse environment file has
its port changed from 5432 to 5433. Nothing is listening there, so every query
fails, `/api/health/` returns 503, and the React frontend — which treats any
failed fetch as an empty result set — renders an empty catalogue. No data has
been touched.

**Why it is realistic.** Port 5433 is what you get on a host that once ran two
PostgreSQL major versions side by side, and it is the number people half-remember
and type. The same shape arrives from a copied `.env` between environments.

**Why the reported symptom is in the wrong component.** This is the brief's whole
point, and the reason it was written as a data-loss report: the coordinator
describes a catalogue that has been emptied and asks for a restore. Acting on the
report as given means restoring a backup over a perfectly intact database — doing
real damage in response to a misdiagnosis. The first move has to be separating
"the page shows nothing" from "there is nothing to show", and that is a single
`curl` against the API.

**The trap.** Making the health check go green by pointing `DATABASE_URL` at a
database that *does* answer — the host PostgreSQL that `leaves` uses is on 5432
and will accept the connection. Health turns green, the list stays empty, and the
fault looks half-fixed. `check.sh` asserts the list endpoint returns rows for
exactly this reason. The lesser trap is rebuilding the frontend, which the brief
invites and which changes nothing.

**Level 2.** One cause, one configuration value, but the symptom points at the
wrong layer and the obvious response to the ticket is destructive.

**Why `PROVEN=unproven` despite having been tested.** It was verified end to end
against a mock `docker compose`, including the trap — but `nurse` now runs as
gunicorn under systemd, because neither public repository ships a Dockerfile.
The branch that will actually execute on the VM is therefore the systemd one,
which restarts the unit so it re-reads its `EnvironmentFile` rather than
recreating a container. That branch has not been run. The compose branch stays
for after s6-07, and the field records the path in use rather than the path that
was convenient to test.
