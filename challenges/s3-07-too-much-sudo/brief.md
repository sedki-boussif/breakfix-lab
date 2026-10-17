Access review, item 4 of 11. Raised by the reviewer, not by a user.

> **Finding.** The account `dev1` holds unrestricted `sudo` without password
> re-authentication. Sampled on the date of review.
>
> **Stated business need.** Restart the web server after a front-end deploy.
>
> **Policy.** Section 4.2: privileged access is granted for a named task and no
> more. Any grant wider than the stated need is a finding regardless of whether
> it has been used.
>
> **Required remediation.** Reduce the grant to the stated need, evidence the
> reduction, and confirm that the account can still perform the task it was
> granted for. Re-tested at the next review.

No outage. Nothing is broken. The account works and will keep working; that is
the problem.
