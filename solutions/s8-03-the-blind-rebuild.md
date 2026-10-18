# s8-03 — The blind rebuild

## The goal
s8-01 again, from a bare image, reading only your own runbooks. The output is
not the server — it is the diff on your documentation.

## Before you start

```bash
# The runbooks must be committed, or the baseline measures nothing.
git -C "$S8_RUNBOOK_DIR" status --porcelain      # must be empty
lab start s8-03-the-blind-rebuild                # prints the baseline sha
# Write the sha down somewhere that is not this VM.
```

## How to work while you are stuck

The discipline is three steps, in this order, and the order is the whole
technique:

1. **Write the gap down**, in the runbook, as a question: *"which directory do
   SSH drop-ins go in, and does sshd need reload or restart?"*
2. **Work it out from the machine** — `systemctl cat`, `sshd -T`, `nginx -T`,
   `journalctl -u`, `--help`. Not from documentation.
3. **Replace the question with the answer, and commit it.** Then carry on.

What makes this work is that step 1 happens while you are still stuck. Written
afterwards, the entry becomes *"configure SSH"*, which is what the runbook
already said.

```bash
# Then, after the rebuild:
lab check s8-03-the-blind-rebuild --arm
sudo reboot
lab check s8-03-the-blind-rebuild --since <baseline>
```

## What the gaps usually turn out to be

Not the big steps — those are in every runbook. In rough order of how often
they are missing:

| Kind of gap | Example |
|---|---|
| Exact flags | `rsync -aHAX --numeric-ids`, and why each letter is there |
| Which directory | `/etc/ssh/sshd_config.d/`, `/etc/nginx/sites-available/` |
| Reload or restart | nginx reloads; sshd reloads; a changed unit file needs `daemon-reload` first |
| Ordering | the firewall before the apps, the seed before the backup, `enable` before the reboot |
| The verification command | "check it worked" versus `sudo sshd -T \| grep passwordauthentication` |
| What normal looks like | the output you should see, so you can tell when you are not seeing it |

The last one is the most valuable and the most often absent. A runbook that
says what the healthy output looks like turns a step from an action into a
check.

## Verification
`lab check s8-03-the-blind-rebuild --since <sha>` — the full s8-01 suite, plus:

- commits in `S8_RUNBOOK_DIR` since the baseline, and lines added by them;
- nothing left uncommitted, which is the usual reason the diff is empty;
- the report recording the time, the gaps, and the conditions it was done
  under.

The check prints `git diff --stat` and the commit list. That output is the
deliverable — keep it with the report.

## Prevention
The lasting fix is to write the runbook *during* the build rather than after
it, which is a habit rather than a document. Two things make it cheap:

- Keep the runbook open in a second pane and paste commands into it as you run
  them, with the output you expected. `history` is a worse version of this and
  still better than memory.
- Record what normal looks like, not just what to do. Six months later the
  question is never "what do I type" — it is "is this right".

Then re-run this challenge in six months. A runbook is not finished; it is
maintained, and the only thing that reveals whether it still works is trying to
use it without help.

## What I did not know before this
How specific the gaps are. Every missing piece was a flag, a directory name, or
an ordering — never a concept. The parts I was worried about forgetting were all
documented; the parts that stopped me were the ones I had never thought of as
knowledge at all.
