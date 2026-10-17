From the developer who maintains the frontend, 15:30:

> The theses API keeps falling over and coming back. I have been getting 502s
> all afternoon, maybe one request in ten, and by the time I open a terminal it
> is healthy again. Times I wrote down: 13:52, 14:06, 14:21, 14:40, 15:12.
>
> It is roughly every fifteen minutes, which smells like a connection pool or a
> keepalive timeout to me. My guess is the database is dropping connections and
> the API is not reconnecting cleanly — we had something like that on another
> project. Can you bump the pool size and see if it settles?
>
> Also, unrelated, the box feels sluggish today. Probably the indexer.

The API is up when you look at it. The other two applications are unaffected.
