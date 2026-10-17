Nothing is failing here, so there is nothing to diagnose — this is about reading what an account can currently do and narrowing it without breaking the one thing it legitimately needs.
`sudo -l -U dev1` lists what sudo believes the account may run, which is the only answer that counts. The grant itself will be in `/etc/sudoers` or a file under `/etc/sudoers.d/`.
The grant is `ALL=(ALL) NOPASSWD: ALL` — every command, as any user, without a password. The stated need is one command.
Write the narrow grant with `visudo -f /etc/sudoers.d/dev1`, which refuses to save a file that would break sudo for everyone. Validate with `visudo -c` before you walk away.
Name the command exactly, with its full path and its arguments: a grant of `/usr/bin/systemctl` with no arguments lets the account restart, stop or mask any unit on the machine, including sshd.
Write the path sudo will actually resolve, not the one your own shell finds. sudo uses its own `secure_path`, so check with `sudo -l` after writing the grant: if the path in the grant is not the one sudo resolves, the command is denied and it looks as though the narrow grant does not work.
After narrowing it, prove both halves: `dev1` can still restart nginx, and `dev1` cannot restart anything else. The check tests both, and requires `sudo -l` to list exactly one permitted command.
