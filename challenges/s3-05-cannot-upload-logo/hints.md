The report is too vague to act on, so get a precise failure of your own first: upload a small file to the endpoint yourself with `curl -i -F` and read the actual status and body instead of "it goes red".
The API answers with 500 and a message naming the path it could not write and why. That is the application telling you exactly what is wrong — the browser was hiding it, not the server.
The uploads directory is a Docker volume mounted into the container. Find where it lives on the host with `docker volume inspect`, then look at the ownership and mode of that path with `ls -ld`.
The container runs as a non-root uid. Compare that uid — `docker compose exec api id` — with who owns the directory on the host. They no longer match.
Give the volume path back to the uid the container runs as, with a mode that lets only that owner write. `namei -l` on the full path shows whether every directory above it is traversable too.
`chmod 777` makes the upload work and is not the fix: it grants write access to every process and every other container that mounts it. The check refuses a world-writable uploads directory, and refuses an api running as root.
