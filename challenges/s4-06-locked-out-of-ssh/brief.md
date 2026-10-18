**Read this before you start it.**

**You will lose SSH to this machine.** That is the exercise, not an accident.

- **Take a snapshot now.** `reset.sh` can undo this only while you still have a
  session; once your session ends you have no way in.
- **Open the hypervisor console before you begin**, and confirm you can log in
  through it. Not "I know where it is" — logged in, now.
- **`break.sh` will make you type `yes-i-have-console`.** Nothing happens until
  you do.
- Do not start this at the end of the day, and do not start it on a machine you
  need for anything else today.

This is the one challenge exempt from the lab's rule that breaks never touch SSH
access. It says so loudly because the rule exists for a reason.

---

The ticket, as it would arrive the morning after a change window:

> Nobody can get into the lab box. I get "connection refused" on port 22 from
> here, and so does Nizar from home. The applications are all still up and the
> website works fine, so the machine is clearly running.
>
> There was a change last night — something about moving SSH off the default
> port to cut down the scanning noise. I don't know if it was finished.

The applications answering is the clue that matters: the machine is healthy and
only your way in is gone.
