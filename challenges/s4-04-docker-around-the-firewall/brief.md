**The goal.** Prove to yourself that `ufw` does not protect a published Docker
port, then fix it two different ways and understand why each works.

This is the single most common way a machine that "has a firewall" is exposed
anyway, and the only way to believe it is to do it.

**Part one — demonstrate the hole.**

1. Publish a container port on all interfaces: add `ports: ["9090:80"]` to a
   service in the stand-in's compose file, or run a throwaway container with
   `-p 9090:80`.
2. Deny it in `ufw`: `sudo ufw deny 9090/tcp`.
3. From **another machine** — your laptop, not the VM — reach
   `http://<LAB_LAN_IP>:9090/`.

It answers. `ufw status` says the port is denied, and the port is open.

**Part two — fix it twice.**

- **Bind to loopback and put nginx in front.** `ports:
  ["127.0.0.1:9090:80"]`. The port is no longer published on the LAN at all, so
  there is nothing for the firewall to have an opinion about. This is what every
  other service in this lab already does, and it is the right default.
- **Filter in the `DOCKER-USER` chain.** `sudo iptables -I DOCKER-USER -p tcp
  --dport 9090 -j DROP`. This is where to put rules that must apply to
  container traffic, because Docker inserts its own rules *before* ufw's.

**The standard this will be checked against:** the denied port is genuinely
unreachable from the LAN address, and the application still works through nginx.

**Write down in the report why ufw was bypassed.** The mechanism — Docker
writing `DOCKER`/`DOCKER-USER` chains into `nat` and `filter` that are
traversed before ufw's `ufw-input` chain — is the thing worth carrying, not the
commands.
