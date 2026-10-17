**Read this before you start it.**

This is the first challenge that cannot be run from a container, a mock, or
anywhere but the lab VM itself, and it is the first one where you must have the
hypervisor open in front of you before you begin.

- **Take a snapshot now.** `reset.sh` cannot undo this one: by the time it
  matters, the machine will not be running the lab.
- **Have console access to hand** — the hypervisor's console, not SSH. The VM
  will not finish booting, so there will be no SSH to connect to.
- **`break.sh` will ask you to type a phrase** confirming both of the above.
  Nothing happens until you do.

---

The ticket, as it would arrive:

> Patching finished at 02:40 and the box has not come back. It answers ping —
> actually no, sorry, it does not. Nothing responds, SSH times out, and the
> console shows a root prompt saying something about emergency mode and
> "Press Enter for maintenance". The apps are all down with it.
>
> It was fine when I rebooted it. The only thing I did before that was tidy up
> the mount table.

Everything is down. You are working from the console, as root, with no network.
