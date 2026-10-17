Handover note from the engineer who took the call, 23:40, mid-investigation:

> Passing this to you — I am out of hours and have not solved it.
>
> `/srv/lab-scratch/logs` is at 98% and climbing was my first read, though it
> looks static now. Writes to it fail. What I have ruled out:
>
> - `du -xh --max-depth=3 /srv/lab-scratch/logs` totals about 4 MB. There is
>   genuinely nothing there.
> - No dot-directories hiding anything, I checked with `find -size +10M` and it
>   returns nothing at all.
> - Not a quota, no quotas configured on this host.
> - `df` and `du` disagree by about 400 MB and I cannot account for it.
>
> My conclusion is that the filesystem is corrupt and needs `fsck`, which needs
> it unmounted, which means taking the log writer down. I did not want to do that
> without a second opinion. **Do not just restart the writer** — if it is
> corruption we will want the process state for the post-mortem.

The filesystem is the log volume. The root volume is fine.
