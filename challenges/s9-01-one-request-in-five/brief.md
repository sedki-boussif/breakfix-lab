From the developer who maintains the frontend, 14:10:

> Something is wrong with the theses API but I can't pin it down. Searches work,
> then one fails with a 502, then the next three are fine. If I hit refresh
> enough times it always comes back.
>
> I've opened it in two browsers and it happens in both, so it's not a cache. It
> feels like maybe one in five? I can't make it happen on demand, which is the
> annoying part — every time I open a terminal to show someone, it works.

Intermittent, unreproducible on demand, and the thing that makes it hard: every
single-shot test you run has an eighty per cent chance of passing.
