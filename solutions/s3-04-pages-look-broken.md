# s3-04 — Pages load but look broken

## Symptom
The leave site renders as unstyled HTML: no colours, content stacked to the left,
links as plain blue underlined anchors. It was reported as an unannounced
redesign, with a request to put the old version back. The application itself
works — login succeeds and records display.

## Investigation

| # | Command | What it showed | What it ruled out |
|---|---------|----------------|-------------------|
| 1 | — | The description itself: no colour, no layout, default link styling, but working forms | This is a page rendering with no CSS. Ruled out a redesign, a rollback and the database before touching the server |
| 2 | `curl -s http://127.0.0.1:8081/etoile-formation-conge/ \| grep -i 'link rel'` | The HTML still asks for its stylesheets | Ruled out a template change: the markup is unchanged, so nothing was redeployed |
| 3 | `curl -i .../static/admin/css/base.css` | `404 Not Found` | The asset is missing, not corrupt and not cached. Confirms delivery, not design |
| 4 | `ls -la /opt/leaves/staticfiles/` | Empty | — |
| 5 | `ls /opt/leaves/staticfiles/staticfiles.json` | Absent | The second half: with `CompressedManifestStaticFilesStorage`, the manifest maps asset names to hashed filenames. Restoring files without rebuilding it still fails |
| 6 | `journalctl -u leaves \| grep -i manifest` | `ValueError: Missing staticfiles manifest entry for ...` on some requests | Explains why some pages error outright rather than merely looking plain |

**Dead end worth recording.** A hard refresh and a different browser, which is
the right instinct for a styling complaint and takes thirty seconds to eliminate.

## Root cause
`STATIC_ROOT` was emptied and the WhiteNoise manifest deleted. The application
serves HTML correctly and every static asset 404s, so browsers render unstyled
markup.

## Fix
```bash
cd /opt/leaves
set -a; . /etc/leaves/leaves.env; set +a
sudo -u www-data ./.venv/bin/python manage.py collectstatic --no-input
sudo systemctl restart leaves
```

As the user the service runs as, or the rebuilt files are owned by root and
WhiteNoise cannot read them — which produces the same 404s and looks like the fix
not working. The restart is so WhiteNoise rescans the directory at startup.

Why not `DEBUG=True`: Django would then serve static files itself and the page
would look correct within seconds. It would also expose tracebacks, settings and
SQL to every user, and leave `STATIC_ROOT` empty, so the next deploy — or
switching DEBUG back — breaks it again. It converts a cosmetic fault into a
disclosure vulnerability.

## Verification
The stylesheet returns 200 with `content-type: text/css`; the page renders
normally; and a URL that cannot exist returns a plain 404 rather than Django's
debug page, proving the assets are being served by WhiteNoise rather than by
DEBUG mode.

## Prevention
- **Check an asset, not just the page.** A monitor that fetches the homepage gets
  200 while the site looks destroyed. Fetch one stylesheet and assert its
  content type; that is one line in s6-04's watchdog.
- **`collectstatic` belongs in the deploy, every time**, not as a step someone
  remembers.
- **`STATIC_ROOT` should not look like clutter.** Keep it outside the application
  directory, or put a `README` in it saying what deletes and rebuilds it.
- **Never leave DEBUG as a diagnostic tool.** If it goes on, it goes off in the
  same command.

## What I did not know before this
A user's wrong diagnosis can be excellent evidence. "No colours, stacked to the
left, blue underlined links" is a precise and complete description of CSS failing
to load — the facts were right and only the conclusion was wrong. And with
manifest storage, restoring the static files alone is not enough: the manifest is
part of the artefact.
