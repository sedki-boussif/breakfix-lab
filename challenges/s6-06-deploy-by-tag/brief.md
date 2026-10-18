**The goal.** Put `$S6_06_APP` on git tags, write a deploy script that takes a
tag name and puts exactly that tag on the machine, then roll back to the
previous tag — and prove the rollback actually changed the running behaviour.

**Why tags and not `git pull`.** `git pull` deploys "whatever is on the branch
right now", which is a different thing on Tuesday than it was on Monday and is
not a thing you can name. You cannot roll back to it, you cannot tell a
colleague which version is live, and when it breaks you cannot say what changed.
A tag is an answer to "what is running?" that stays true. The check asserts no
step used `git pull`, and it means it.

**The work:**

1. **Make the checkout a repository you control tags in.** It is a clone of a
   public repository; add your own tags on top — `v-lab-1`, `v-lab-2`, or dates.
   Two tags at minimum, with a **visible difference** between them, because the
   rollback has to be observable: change a template string, a version constant,
   anything the running application will show you.
2. **Write the deploy script.** It takes a tag name as its argument and:
   - refuses a tag that does not exist, **before** touching anything;
   - checks out exactly that tag — detached HEAD is correct here, not a branch;
   - does whatever the application needs afterwards (dependencies, migrations,
     static files, restart);
   - **records what it deployed** in `$S6_06_DEPLOY_STATE`, outside the
     checkout, with the tag and the time;
   - verifies the app answers before declaring success, and tells you plainly
     if it does not.
3. **Deploy the older tag, then the newer one**, and watch the visible
   difference appear.
4. **Roll back** to the older tag using the same script, and watch it go away
   again.

**Why the record lives outside the checkout.** `git describe` can tell you what
the working tree is at — until someone runs a command that moves it, and then
the only record of what you *deployed* is gone. A deploy that cannot be
reconstructed after the fact is a deploy you have to take on trust.

**The standard this will be checked against:**

- A deploy script exists, is executable, and **refuses an unknown tag** without
  changing anything.
- The checkout has **at least two tags**, and is currently at a tag — the
  working tree is **clean** and `HEAD` is **exactly** a tag's commit, not a
  branch tip, not a commit in between.
- `$S6_06_DEPLOY_STATE` records the deployed tag, and it **matches what is
  actually checked out**. A record that has drifted from reality is worse than
  no record.
- **The rollback is observable.** The check deploys the other tag with your
  script and requires the application's response to **change**, then deploys
  back and requires it to change back. A rollback nobody can see is a rollback
  nobody can verify.
- **No `git pull` anywhere** — not in the script, not in the runbook you write.
- The app answers after every deployment.

**Note.** The check runs your deploy script, twice, against the real
application. It puts you back on the tag you started on when it is done,
whichever way the assertions went.
