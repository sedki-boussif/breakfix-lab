Nobody redesigned anything. Take the description literally: no colours, no layout, links styled as plain anchors — that is a page rendering with none of its stylesheets, which is a delivery problem, not a design change.
Open the page with `curl -s | grep -i 'link rel'` to find the stylesheet URLs the HTML asks for, then `curl -i` one of them. The HTML is fine; see what happens to the asset.
The stylesheet returns 404. The application serves its own static files through WhiteNoise, so the question is what WhiteNoise is serving them *from*.
Look in the directory the app collects static files into — `STATIC_ROOT` — and at the manifest beside it. Both the files and the manifest that maps names to hashed filenames are gone.
`python manage.py collectstatic --no-input` rebuilds both, as the deploy script does. Run it as the user the service runs as, then restart the service so WhiteNoise rescans.
Do not fix this by turning DEBUG on. With DEBUG=True Django serves static files itself and the page looks correct again, with the real problem untouched and tracebacks exposed to users. The check requires DEBUG to stay off.
