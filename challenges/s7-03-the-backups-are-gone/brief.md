From Nizar, 08:50, having already been at it for an hour:

> I need help. The placements database is empty — not broken, empty, the tables
> are there and there is nothing in them. I do not know what did it.
>
> I went to restore and the local repository is gone. The whole directory. So I
> went to the off-site one and restic says the newest snapshot there is
> corrupted — something about a pack file. I tried `restic check` and it listed
> errors, and then I tried `restic repair` and I am not sure what that did.
>
> I have stopped touching it. Please take over.

He has stopped, which is the single most useful thing he did. Two faults are
tangled here and he has told you about both without separating them.
