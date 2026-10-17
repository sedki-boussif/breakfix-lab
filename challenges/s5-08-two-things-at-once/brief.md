Two reports, eleven minutes apart, which do not agree with each other.

**09:02, from HR:**

> None of the sites are loading at all. Not slow — nothing. The browser says it
> cannot connect. I have tried the leave one and the theses one and both do the
> same thing, so I assume the server is off.

**09:13, from Nizar:**

> I had a look and got it partly back — the pages come up now but the leave app
> gives "502 Bad Gateway". The theses one seems fine. I restarted nginx and that
> is when the pages started coming up, so I think the 502 is a separate thing
> that was there all along and we just could not see it.

He is right that it is separate, and wrong that it was invisible — it was
unreachable, which is not the same thing.
