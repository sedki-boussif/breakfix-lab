# SOLO.md — running this lab with nobody to ask

Everything here assumes: it is late, there is no internet, and the only things
you have are this repository and the VM. No command in this file needs either.

**Start here, always:**

```bash
lab doctor
```

It reads only. If it reports failures, fix those first and in order — a broken
lab produces faults that look exactly like challenges, and you will spend an
hour debugging a challenge that was fine. If `lab doctor` is clean, the problem
is the challenge or it is you, and §1 tells you which.

---

## 1. Is the check broken, or have I not fixed it?

This is the question that wastes the most time, and it is decidable in about two
minutes. Run these four in order and stop at the first that answers.

### Step 1 — does the check pass on an unbroken lab?

```bash
lab reset <id>          # put everything back
lab check <id>          # now ask again
```

- **Passes** → the check is fine. The fault is still in place, or your fix is
  incomplete. Go to §2 and read what it actually wants.
- **Still fails** → the check disagrees with your machine, not with your fix.
  Go to step 2.

This single comparison settles it most of the time, and it costs one reset.

### Step 2 — which assertion, and what did it say?

Every failure prints a reason on the second line. Read it literally:

| What you see | What it means |
| --- | --- |
| `FAIL  …` with a reason | The thing it names is genuinely not true yet |
| `FAIL  … cannot verify absence: <fn> did not find an instance planted on purpose` | **The check's own detector is broken on this machine.** Not your fault. §4 |
| `FAIL  … assertion timed out after 30s` | A command the check runs hangs here. §4, and raise `ASSERT_TIMEOUT` |
| `SKIP  …` | A conditional assertion that could not run — usually an unset `lab.conf` value |
| `97` as the exit code | `lab_guard` refused: the marker, or the hostname. `lab doctor` |

`cannot verify absence` and `assertion timed out` are the two that mean **the
check is wrong, not you**. Everything else is a real claim about your system.

### Step 3 — run the check's own commands by hand

A check is a shell script you can read. Find the assertion that failed and run
the command inside it yourself:

```bash
grep -n 'the exact assertion text' challenges/<id>/check.sh
sed -n '1,200p' challenges/<id>/check.sh      # read the whole thing; they are short
bash -x challenges/<id>/check.sh 2>&1 | tail -60    # see every command it ran
```

`bash -x` is the one that matters. It shows you the actual command, the actual
values after expansion, and where it stopped.

### Step 4 — compare against the author's notes

```bash
cat challenges/<id>/notes.md
```

`notes.md` says what the fault really is, why it is realistic, and — under **The
trap** — the wrong fix the check deliberately refuses. If your fix is the trap,
the check is right and you are not. If `notes.md` describes a machine that does
not match yours, the check needs adjusting: §4.

Read `solutions/<id>.md` only after that. It is the full answer and it spends
the challenge.

---

## 2. Reading a check to see what it actually wants

Checks are deliberately short and in a fixed shape. For any challenge:

```bash
sed -n '1,30p' challenges/<id>/check.sh     # the header comment states the intent
grep -nE '^assert_|^ *assert_' challenges/<id>/check.sh
```

That `grep` is the complete list of what must be true, in order. The assertion
names are the vocabulary:

| Assertion | What has to be true |
| --- | --- |
| `assert_http "<desc>" <url> 200` | That URL returns exactly that status |
| `assert_http_header … 'content-type:…'` | The response's headers match |
| `assert_cmd "<desc>" <command…>` | That command exits 0 |
| `assert_not "<desc>" <command…>` | That command exits **non-zero** |
| `assert_service "<desc>" <app> <role>` | The service is running, in whichever mode `lab.conf` says |
| `assert_eventually "<desc>" <seconds> <command…>` | It becomes true within that window — so a slow start is fine |
| `assert_below "<desc>" <actual> <limit>` | A measurement is under a threshold |
| `assert_equal "<desc>" <a> <b>` | Two values match — often a restart counter before and after |
| `assert_absent "<desc>" <detect> <plant> <clean>` | Something is gone, **and** the detector was proved against a planted instance first |
| `assert_summary` | Sets the exit status: 0 only if every assertion passed |

Two things to know about the shape:

- **Assertions are independent.** One failure does not stop the rest, so the
  output is the complete list of what is still wrong. Fix them top-down.
- **A positive claim is its own evidence; an absence claim carries a control.**
  If you see `(detector proved against a planted instance)` on a pass, the check
  verified its own search before trusting a clean result.

---

## 3. Updating PROVEN after a real run

`meta` carries `PROVEN=`, which records **how a challenge has actually been
verified** — not whether it is written. It is a record, nothing enforces it, and
it is the only thing that will tell you later what you can trust.

```bash
grep PROVEN challenges/*/meta | sed 's|challenges/||'
make selftest                 # prints the counts, and names what is unproven
```

After you have run a challenge for real on the VM — break, check fails, fix,
check passes, reset:

```bash
sed -i 's/^PROVEN=.*/PROVEN=real/' challenges/<id>/meta
make selftest                 # confirms it is still a valid value
git add challenges/<id>/meta && git commit -m "s3-06: PROVEN=real, verified on the VM"
```

The five permitted values, and what each one honestly claims:

| Value | Claim |
| --- | --- |
| `real` | Exercised against the real thing on the lab VM |
| `mock-systemd` | Exercised against a stand-in service manager — logic and traps proved, the real app not |
| `mock-compose` | Same, against a stand-in `docker compose` |
| `mock-process` | Same, against a plain background process |
| `unproven` | Written and linted, never run |

**Downgrade as well as upgrade.** If a challenge's live path changes — s3-02
went from compose to systemd and its tested branch stopped being the one that
runs — set it back to `unproven` and write why in `notes.md`. A `PROVEN` field
that only ever goes up is decoration.

---

## 4. The check is wrong on my hardware

Sometimes the check, not the fix, is what disagrees with your machine. Three
honest options, in order of preference.

### 4a. Tune the threshold in `lab.conf`

Most numbers a check compares against are configurable, precisely so you do not
have to edit a check:

```bash
grep -nE '^[A-Z_]+=' lab.conf | grep -iE 'timeout|survive|floor|mb|inodes|age|placements'
```

| If this fails | Change this |
| --- | --- |
| `assertion timed out` on a slow VM | `ASSERT_TIMEOUT` (default 30) |
| s5-04's survival window is too long to sit through | `S5_SURVIVE_SECONDS` |
| s5-04 says the memory limit is sane when it is not | `S5_MEM_FLOOR_MB` |
| s5-01/s5-03 need a bigger or smaller filesystem | `S5_UPLOADS_MB`, `S5_LOGS_MB` |
| s5-02 exhausts too slowly | `S5_SPOOL_INODES` |
| s9-07 cannot see the index difference | `SEED_PLACEMENTS`, then re-seed |
| s5-09 calls a fresh report stale | `LAB_JOB_MAX_AGE_H` |

Change the value, re-run the check, and **write the change in `notes.md`** under
a heading `## Local deviations`. In six weeks you will not remember.

### 4b. Edit the assertion

If the check asserts something untrue of your machine — a path that does not
exist here, a unit under another name, a tool you do not have — edit it. It is
your lab.

```bash
cp challenges/<id>/check.sh challenges/<id>/check.sh.orig   # keep the original
# edit, then:
make lint                  # must stay clean: shebang, set -euo pipefail, inherit_errexit
lab reset <id> && lab check <id>     # must PASS on an unbroken lab
bash challenges/<id>/break.sh && lab check <id>   # must FAIL on a broken one
bash challenges/<id>/reset.sh
```

Those last three lines are the whole discipline: **a check must pass when fixed
and fail when broken.** If it does not do both, it is not a check, and nothing
else about it matters. Then set `PROVEN=real` and note the edit.

### 4c. Disable it, visibly

If a challenge cannot work on your hardware — s6-01 without a second disk,
s4-01 without a bridged adapter — do not delete it and do not leave it to
confuse you later:

```bash
printf '\nSKIP=1  # no second disk on this hypervisor, 2026-10-18\n' >> challenges/<id>/meta
```

Then `lab list` still shows it, `notes.md` still explains it, and you have the
reason recorded. Nothing reads `SKIP`; it is a note to yourself, which is the
point. If you want it out of `make test` as well, add `RISK=irreversible`, which
`make test` already skips.

---

## 5. Writing a new challenge

Seven files, one directory. Copy an existing one of the same shape rather than
starting blank — s3-01 for a service fault, s5-01 for a resource fault, s3-07
for a system/permissions one:

```bash
NEW=s3-08-my-new-fault
cp -r challenges/s3-01-leave-app-502 "challenges/$NEW"
cd "challenges/$NEW"
sed -i "s/s3-01-leave-app-502/$NEW/g" break.sh check.sh reset.sh notes.md
$EDITOR meta brief.md hints.md notes.md break.sh check.sh reset.sh
cd ../.. && touch "solutions/$NEW.md"
make selftest        # tells you exactly what is missing
```

`make selftest` is the specification, enforced: seven files, a solution file, at
least four hints, a valid `TYPE`, `LEVEL` 1–5, `SNAPSHOT`, `RISK`, `PROVEN`, and
`NEEDS` that reference real ids.

**`meta`** — every field, no blanks:

```sh
STAGE=3
TYPE=incident          # or mission
TITLE="What the ticket would be called"
LEVEL=2                # 1 obvious · 2 config · 3 hidden cause · 4 two faults · 5 security
APPS=leaves            # stages | leaves | nurse | system
NEEDS=                 # ids that must be passed first, space separated
SNAPSHOT=deployed      # or clean
RISK=                  # or irreversible, if reset.sh cannot undo it
PROVEN=unproven        # until you have actually run it
```

**The five rules that make a challenge worth keeping**, each learned by getting
it wrong:

1. **`brief.md` describes symptoms, never causes.** A time, an impact, and the
   voice of whoever would notice. Vary the reporter: someone wrong about the
   cause, someone who already made it worse, a monitoring alert, someone vague,
   someone whose symptom is in a different component from the fault.
2. **`break.sh` is guarded and idempotent.** `lab_guard` first, always. Back up
   anything you modify with `lab_backup_file`. Running it twice must not deepen
   the damage — test that.
3. **`check.sh` proves the end state, not the symptom.** And name the trap: if
   there is an obvious wrong fix that makes the symptom go away, the check must
   refuse it. Write it in `notes.md` under `**The trap.**`
4. **Every absence claim carries a positive control.** Use
   `assert_absent <desc> <detect_fn> <plant_fn> <clean_fn>`, and **plant the
   control where the real claim lives** — a control pointed somewhere else
   proves only that the detector works. If you cannot plant it there, the claim
   probably wants to be positive instead.
5. **`reset.sh` is harmless twice**, and `hints.md` is four to six lines:
   which layer, which tool, what the tool shows, the cause, the fix.

Then prove it the way §4b says: passes fixed, fails broken, `make lint` clean.

---

## 6. break.sh left the VM in a state reset.sh will not clear

In order of how much it costs you. Try them in this order.

### 6a. Run reset again, and read what it says

```bash
bash -x challenges/<id>/reset.sh 2>&1 | tail -40
```

`reset.sh` is written to be harmless twice. `bash -x` shows which step failed —
usually a path that moved, or a service that was already stopped.

### 6b. Undo it from the recorded state

`break.sh` records what it changed, and keeps pristine copies of anything it
edited:

```bash
ID=<id>
cat ~/.breakfix-progress/state/$ID/vars              # what it recorded
ls -la ~/.breakfix-progress/state/$ID/backup/        # pristine copies
```

Filenames in `backup/` are the original path with `/` replaced by `__`, so
`__etc__leaves__leaves.env` is `/etc/leaves/leaves.env`. Put one back by hand:

```bash
sudo cp ~/.breakfix-progress/state/$ID/backup/__etc__systemd__system__leaves.service \
        /etc/systemd/system/leaves.service
sudo systemctl daemon-reload && sudo systemctl restart leaves
```

### 6c. Clear the usual residue

Four things account for nearly every stuck state:

```bash
# A unit that hit its start limit refuses to start even once it is fixed.
sudo systemctl reset-failed <unit>

# A loop filesystem still mounted from a stage 5 challenge.
mount | grep /srv/lab-scratch
sudo umount /srv/lab-scratch/*   2>/dev/null
sudo losetup -a                  # ours are backed by /var/lib/breakfix-lab/*.img
sudo losetup -d /dev/loopN
sudo rm -f /var/lib/breakfix-lab/*.img

# A process a break started and left running.
pgrep -af 'apt-cache-gen|indexer-warmup|telemetry-agent|leaves-logwriter'
sudo pkill -f <that name>

# A compose override a break wrote.
ls -la /opt/*/compose.override.yaml
```

Then `lab doctor`, which checks for exactly this residue and names what is left.

### 6d. Forget the challenge's state and start over

The lab's own record can be wrong without the machine being wrong:

```bash
rm -rf ~/.breakfix-progress/state/<id>       # what break.sh recorded
rm -f  ~/.breakfix-progress/progress/<id>    # timer, hints, pass status
```

This loses your timer and hint count for that challenge and nothing else. It
does **not** undo anything on the machine.

### 6e. Roll back the snapshot

This is not failure, it is the design. Two challenges cannot be undone any other
way (`s5-07`, `s7-07`), and the whole lab assumes you will use it:

```
Restore the `deployed` snapshot.
Then: cd ~/breakfix-lab && lab doctor
```

After a rollback, `lab.conf` is whatever it was when you snapshotted. If you
restore `clean` rather than `deployed`, redo SETUP.md §4 — `LAB_LAN_IP` is empty
in that snapshot.

### 6f. When the VM will not boot

You are at the hypervisor console, as root, with no network. This is s5-07's
subject and the recovery is the same whatever caused it:

```bash
mount -o remount,rw /        # the root filesystem starts read-only
systemctl --failed           # what gave up
journalctl -xb | tail -40    # why
cat /etc/fstab               # the usual culprit
mount -a                     # MUST be silent before you trust a reboot
```

If `mount -a` complains, fix or comment the line it names. If you cannot see it
in ten minutes, roll back the snapshot — that is cheaper than being clever at
one in the morning.

---

## 7. The five commands worth memorising

```bash
lab doctor                      # is the lab the problem?
lab next                        # what am I ready for?
bash -x challenges/<id>/check.sh 2>&1 | tail -40     # what did the check actually do?
cat challenges/<id>/notes.md    # what is the fault, and what is the trap?
make lint && make selftest      # did I break the repo?
```

And the one habit: **`lab report <id>` while it is fresh.** The dead ends are the
valuable part, and in a month the report is the only thing left of the hour you
spent.
