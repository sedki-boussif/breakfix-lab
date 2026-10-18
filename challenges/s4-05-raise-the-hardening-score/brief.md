**The goal.** Measure how hardened this machine is, improve it deliberately, and
measure again — so that "hardened" becomes a number with a date on it rather
than a feeling.

```bash
sudo lynis audit system
```

It prints a hardening index out of 100 and a list of suggestions. Record the
score. Then fix the **top five findings you agree with**, and re-run.

**The standard this will be checked against:**

1. The score **improved** against the baseline recorded when you started.
2. **SSH is key-only, with root login disabled** — and verified by asking sshd
   what it will actually do, not by reading the config file.
3. The **open-port list matches `EXPECTED_PORTS` exactly** — nothing extra, and
   nothing expected missing.

**Fix only what you agree with, and write down what you rejected and why.** A
hardening score is a checklist, not a judgement: lynis will suggest things that
are wrong for this machine, and accepting all of them uncritically is how a
server ends up unable to do its job. The rejections are the interesting half of
the report.
