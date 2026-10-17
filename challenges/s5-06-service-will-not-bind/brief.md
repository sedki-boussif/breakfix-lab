Phone call from Nizar, mid-deploy, reading from his terminal:

> I was putting the new leave form live so I restarted the service and now it
> will not come back. It says — hold on — "Error: [Errno 98] Address already in
> use" and then a load of Python, and then systemd says the whole thing failed.
>
> I have restarted it four times. Same every time. I have not changed any
> config, I only pulled the new templates. Do you want me to reboot the box?

He has the exact error and no idea what it means, which is the most useful kind
of call to get. Nothing was reported before the restart: the old process was
serving happily until he stopped it.
