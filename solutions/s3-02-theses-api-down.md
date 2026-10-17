# s3-02 — Theses API is down, site shows an empty list

## Symptom
The theses catalogue renders normally but lists nothing, for any search. It was
reported as data loss — "the import must have deleted everything" — with a
request to restore about three thousand records.

## Investigation

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | `curl -i http://127.0.0.1:8000/api/health/` | `503` with `{"detail": "database unreachable"}` | Ruled out the frontend, the browser, and the search itself. It also ruled out data loss: the API cannot reach its database, so nothing can have read it to delete anything |
| 2 | `curl -s http://127.0.0.1:8000/api/theses/` | An error, not an empty list | Separated "the page shows nothing" from "there is nothing to show" — the distinction the whole ticket turns on |
| 3 | `docker compose -p nurse ps` | api `Up`, db `Up (healthy)` | Ruled out a stopped database. Both halves are running; they are not talking |
| 4 | `docker compose -p nurse logs api --tail 50` | `connection to server at "db", port 5433 failed: Connection refused` | Named the port. This is the answer, four commands in |
| 5 | `docker compose -p nurse exec db pg_isready` | `/var/run/postgresql:5432 - accepting connections` | Confirms the mismatch: the database is on 5432 and the api is dialling 5433 |
| 6 | `grep DATABASE_URL /opt/nurse/.env` | `...@db:5433/nurse` | — |
| 7 | `docker compose -p nurse exec db psql -U nurse_app -d nurse -c 'SELECT count(*) FROM theses_thesis'` | 3000 | The records never went anywhere. Worth running *before* telling the coordinator anything |

**Dead end worth recording.** Rebuilding the frontend, which the brief all but
asks for. It takes several minutes and changes nothing, because the bundle was
never the problem.

## Root cause
`DATABASE_URL` in the nurse environment file named port 5433, where nothing is
listening. Every query failed, the health endpoint returned 503, and the frontend
rendered a failed fetch as an empty catalogue.

## Fix
```bash
sudo sed -i -E 's|^(DATABASE_URL=.*):5433/|\1:5432/|' /opt/nurse/.env
cd /opt/nurse && docker compose up -d --force-recreate api
```

`--force-recreate`, not `restart`: an `env_file` is read when the container is
created, so a restart keeps the old value and makes a correct fix look wrong.

Why this rather than a workaround: the alternative is to make 5433 work — publish
the database on a second port, or add a port mapping — which leaves two
contradictory truths in the configuration for the next person to find.

## Verification
`/api/health/` returns 200, the list endpoint returns records, and the row count
in the database matches what it was before. Then `docker compose up -d
--force-recreate api` again and re-check, proving the fix is in the environment
file rather than in a container that happens to be running.

## Prevention
- **A health check that is actually checked.** The endpoint already reported 503
  correctly. Nothing was watching it. This is s6-04's job and it would have
  caught this within a cycle.
- **A frontend that distinguishes empty from failed.** "No records found" and "I
  could not ask" must not render identically; that single UI decision caused a
  data-loss report.
- **One source of truth for the database port**, interpolated into both the
  compose file and the environment rather than typed twice.
- **Never act on a reported cause.** The requested remediation — restore the
  catalogue — would have overwritten an intact database. Reproduce the symptom
  yourself before touching data.

## What I did not know before this
`docker compose restart` does not re-read `env_file`; only recreating the
container does. And a 503 from a health endpoint is better news than a 200 with
an empty list, because it tells you the data layer is unreachable rather than
empty.
