# s6-06 — Deploy by tag, and roll back

## The goal
Deploy a named version, roll back to the previous named version, and be able to
show that the rollback changed something.

## The tags

```bash
cd /opt/leaves
git tag -a v-lab-1 -m 'baseline'
# change something the running page actually shows
sed -i 's|Demandes de congé|Demandes de congé (v2)|' \
  leave_management/templates/leave_management/base.html
git commit -am 'visible change for the rollback drill'
git tag -a v-lab-2 -m 'visible change'
git tag
```

Annotated (`-a`) rather than lightweight: it carries a message, an author and a
date, and in six months that is the only explanation of what the tag was for.

## The deploy script

```bash
#!/usr/bin/env bash
# /usr/local/bin/deploy.sh <tag> — put exactly that tag on this machine.
set -euo pipefail

tag="${1:?usage: deploy.sh <tag>}"
dir=/opt/leaves
state=/var/lib/breakfix-lab/deployed-tags
url=http://127.0.0.1:8081/etoile-formation-conge/

# Validate BEFORE touching anything. refs/tags/ spelled out, because a bare
# name also matches a branch — and a typo that happens to be a branch name
# would deploy the branch and look like it worked.
git -C "$dir" rev-parse -q --verify "refs/tags/${tag}" >/dev/null || {
  printf 'no such tag: %s\n' "$tag" >&2
  printf 'known tags: %s\n' "$(git -C "$dir" tag | tr '\n' ' ')" >&2
  exit 2
}

# Detached on purpose. A branch created at the tag moves the next time anyone
# pulls, and then the "fixed version" is not fixed.
git -C "$dir" checkout -q --detach "refs/tags/${tag}"

# Whatever this application needs afterwards.
sudo -u www-data /opt/leaves/.venv/bin/pip install -q -r requirements.txt
sudo install -d -o www-data -g www-data /var/log/leaves
( set -a; . /etc/leaves/leaves.env; set +a
  /opt/leaves/.venv/bin/python manage.py migrate --noinput
  /opt/leaves/.venv/bin/python manage.py collectstatic --noinput )
systemctl restart leaves

# Record it OUTSIDE the checkout, before declaring anything.
printf '%s %s %s\n' "$(date -Is)" "$tag" "$(git -C "$dir" rev-parse --short HEAD)" \
  >> "$state"

# And verify, because a deploy script that reports success on a broken
# deployment is worse than one that does nothing.
for _ in $(seq 1 15); do
  if curl -fsS -o /dev/null --max-time 5 "$url"; then
    printf 'deployed %s\n' "$tag"; exit 0
  fi
  sleep 2
done
printf 'deployed %s but %s does not answer\n' "$tag" "$url" >&2
exit 3
```

## The drill

```bash
sudo deploy.sh v-lab-1
curl -s "$LEAVES_URL" | grep -o 'Demandes[^<]*'      # baseline wording

sudo deploy.sh v-lab-2
curl -s "$LEAVES_URL" | grep -o 'Demandes[^<]*'      # (v2) appears

sudo deploy.sh v-lab-1                                # the rollback
curl -s "$LEAVES_URL" | grep -o 'Demandes[^<]*'      # (v2) is gone

cat /var/lib/breakfix-lab/deployed-tags               # four lines of history
lab check s6-06-deploy-by-tag
```

The rollback is the same command with a different argument. If rolling back
needs a different procedure from deploying, it is a procedure you will be
improvising during an incident — and the entire value of this pattern is that
the rollback is already tested, because it is the thing you have now done four
times.

## Why not `git pull`

| | `git pull` | a tag |
|---|---|---|
| What is deployed | whatever the branch is at, at that moment | a named, fixed commit |
| "What is running?" | unanswerable | the tag name |
| Roll back | to what? | the previous tag |
| What changed | unknown | `git log v-lab-1..v-lab-2` |

`git fetch --tags` is fine — fetching was never the problem. The merge is what
makes the deployed artefact unnameable.

## Verification
`lab check s6-06-deploy-by-tag` runs your script twice against the real
application and requires the response to change and change back, with a control
first: it compares two requests *before* deploying anything, and abandons the
assertion if they already differ. "It changed" proves nothing if the page
changes on its own.

It also requires that an unknown tag is refused **without moving HEAD** —
validation after the destructive step is not validation.

## Prevention
Keep the deploy record. `git describe` tells you what the working tree is at,
which stops being the deployment's history the moment anyone runs a git command
in that directory. A file of `timestamp tag sha` lines answers the question you
actually have during an incident, and it costs one line in the script.

Then tag before you need to. A tag made at the moment of deployment is free; a
tag you wish existed, reconstructed afterwards from the reflog, is an
afternoon.

## What I did not know before this
That `git rev-parse --verify <name>` matches branches as well as tags, so
validating a tag name needs `refs/tags/` spelled out — otherwise a typo that
collides with a branch name deploys the branch and every check downstream
reports success.
