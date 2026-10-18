Stop testing once. A fault that appears in one request in five needs a loop, not a request: `for i in $(seq 1 50); do curl -s -o /dev/null -w '%{http_code} ' <url>; done; echo`. Make the intermittency visible before you try to explain it.
Now you have a pattern rather than an anecdote. Roughly one in three or one in five failing, and consistent across repeats, means something is being selected round-robin — a load balancer with members, a pool with entries, a DNS name with several addresses.
nginx is in front of this API. `sudo nginx -T | grep -A10 upstream` prints the running configuration including any upstream block and its members. Count them, and look at each.
One member points somewhere nothing is listening. `sudo ss -ltnp` tells you which of those addresses actually has a service on it.
Fix the member rather than deleting it: the capacity was presumably there for a reason, and a one-member upstream is a different configuration from a three-member one. The check asserts the member count is intact.
Then prove it the same way you found it — a hundred requests in a row, all 200. A single successful request proves nothing here, which is the whole lesson.
