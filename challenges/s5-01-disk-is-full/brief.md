From Nizar, 10:50, after about an hour of his own:

> The uploads volume filled up overnight. `/srv/lab-scratch/uploads` is at 100%
> and the app cannot write to it, so the open-day pack has not been generated.
>
> I have already cleared what I could — I deleted the old application logs under
> `/var/log/leaves` and emptied a few caches — and it freed almost nothing, so
> whatever is eating it is not logs. I also ran `du -sh /srv/lab-scratch/uploads/*`
> and the total comes to about nothing, which does not add up. I am starting to
> wonder whether `df` is lying.
>
> I have not rebooted. Tell me what else to try and I will do it.

The filesystem in question is the uploads volume, not the root volume. The three
applications are all still answering.
