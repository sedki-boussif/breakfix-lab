Ticket raised by the registry clerk, 08:30:

> The disk is full on the server. I get "No space left on device" every time I
> try to save anything to the spool folder, and the import will not run at all.
>
> I know it is the disk because our IT person showed me how to check once and I
> ran it myself: `df -h /srv/lab-scratch/spool` says the filesystem is only 3%
> used, which cannot be right if it is out of space, so the disk must be broken
> or the number must be wrong. Could someone please add more disk?

The filesystem she is talking about is the spool volume,
`/srv/lab-scratch/spool`. The root volume is fine and the three applications are
answering normally.
