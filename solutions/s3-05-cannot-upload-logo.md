# s3-05 — Nobody can upload the school logo

## Symptom
Uploading an image to the placements app does nothing, or shows an error. The
report is vague: no status code, no message, no timestamp beyond "this morning",
and no reproduction.

## Investigation

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | `curl -i -F 'file=@/tmp/x.png' http://127.0.0.1:8080/api/uploads/` | `500` with `{"detail":"cannot write /app/uploads/x.png: Permission denied"}` | Turning "it goes red" into a status code and an errno. Ruled out the browser, the file size, the file type and the network in one command |
| 2 | `curl -fsS http://127.0.0.1:8080/api/health/` | 200 | Ruled out the database and the application generally. Only writes fail |
| 3 | `docker compose -p stages exec api id` | `uid=10001(appsvc)` | Establishes who the writer is |
| 4 | `docker volume inspect -f '{{.Mountpoint}}' stages_uploads` | `/var/lib/docker/volumes/stages_uploads/_data` | Where the volume really lives, rather than guessing |
| 5 | `ls -ld /var/lib/docker/volumes/stages_uploads/_data` | `drwxr-xr-x root root` | The answer: owned by root, mode 755, and the writer is uid 10001 |
| 6 | `sudo namei -l /var/lib/docker/volumes/stages_uploads/_data` | Every parent traversable | Rules out a parent-directory permission problem, which presents identically |

**Dead end worth recording.** Looking inside the container first —
`docker compose exec api ls -ld /app/uploads` — shows root ownership too, which
is true but not where the fix goes. The mount's ownership comes from the host.

## Root cause
The uploads volume's directory on the host was owned by root with mode 755, so
the api container — which runs as uid 10001 — could not write to it. Nothing
about the application changed.

## Fix
```bash
P=$(sudo docker volume inspect -f '{{.Mountpoint}}' stages_uploads)
sudo chown 10001:10001 "$P"
sudo chmod 775 "$P"
```

Why the uid rather than a name: the host has no `appsvc` user, and does not need
one. The number is what the kernel compares.

Why not `chmod 777`: it makes the upload work and grants write access to every
process on the host and every other container that mounts the volume. It also
leaves whatever produced a root-owned directory free to do it again. Why not run
the container as root: writes then succeed because everything succeeds, which
removes the only boundary the upload path had.

## Verification
A file is uploaded through the endpoint and read back through the API; `namei -l`
shows a fully traversable chain; the directory is not world-writable; and the api
still reports a non-zero uid.

## Prevention
- **A write check in the watchdog.** The health endpoint returned 200 throughout.
  A check that writes a byte to the uploads path and deletes it would have caught
  this; "can the app do its job" is not the same question as "is the app up".
- **Find out what made it root-owned** — almost always a restore or a backup
  script running as root — and fix that, or it recurs.
- **Declare the ownership in the deployment**, not by hand: an init step that
  chowns the volume to the image's uid on every `up`.
- **Surface server errors in the UI.** The API said exactly what was wrong and
  the user reported "it goes red". That gap cost most of the diagnosis time.

## What I did not know before this
A `chown` in a Dockerfile applies to the image's copy of a directory, and is
completely hidden by a volume mounted over the same path at run time. Ownership
of a named volume is whatever the host says it is, and the image cannot fix it.
