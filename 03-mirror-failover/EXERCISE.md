# Exercise - set up a two-member mirror and fail over

The stack starts with both members licensed, healthy and journalled, each with an
empty `MIRRORDATA` database and a `MIRRORNS` namespace over it. Their ISCAgents are
already listening on 2188 - `iris-main` starts the agent by default, so there is
nothing to do for that prerequisite.

Everything below is deliberately left undone. Do it in the portal; `setup/` holds the
same steps as scripts, for resetting the environment or checking an answer.

| Member | Portal | Role after setup |
|---|---|---|
| A | http://localhost:63773/csp/sys/UtilHome.csp | primary |
| B | http://localhost:63774/csp/sys/UtilHome.csp | backup |

Log in as `SuperUser` / `SYS`. Each portal is bound to one member only, so the two
show the mirror from different sides - that is what makes the takeover visible.

There is no arbiter and no virtual IP in this stack. Both omissions are deliberate;
see the header of `docker-compose.yml`.

## 1. Enable the mirror service on both members

System Administration > Security > Services > `%Service_Mirror` > tick *Enabled*.
(Page class `%CSP.UI.Portal.Services`.)

It is off in a fresh instance. Do it on **both** members - the mirror pages stay
mostly empty until it is on.

**Observable result:** System Administration > Configuration > Mirror Settings now
offers *Create a Mirror* and *Join as Failover*.

## 2. Create the mirror set on member A

Mirror Settings > *Create a Mirror*. (Page class `%CSP.UI.Portal.Mirror.Create`.)

- Mirror name: `TRAINMIRROR`
- Member name: `MEMBERA`
- Use SSL/TLS: **off**. A mirror normally requires TLS; it is off here so the
  exercise is about mirroring rather than about certificates.
- Arbiter, virtual IP: leave empty.
- Agent address / mirror address / superserver address: `mirror-a`. Use the **service
  name**, not `localhost` - member B resolves this name on the stack network, and
  `localhost` there would mean member B itself.

**Observable result:** Mirror Monitor (`%CSP.UI.Portal.Mirror.Monitor`) shows
`MEMBERA` as `Primary`, status `Active`.

## 3. Add the database to the mirror on member A

Mirror Monitor > *Add databases to mirror*, and pick `MIRRORDATA`.

**Observable result:** `MIRRORDATA` is listed as a mirrored database of
`TRAINMIRROR`, and its journalling stays on.

## 4. Join member B as the second failover member

On member B's portal: Mirror Settings > *Join as Failover*. (Page class
`%CSP.UI.Portal.Mirror.JoinFailover`.)

- Mirror name: `TRAINMIRROR`
- Agent address of the primary: `mirror-a`, port `2188`
- Instance name on the primary: `IRIS`
- Member name: `MEMBERB`
- Its own agent / mirror / superserver address: `mirror-b`

With TLS off the joining member registers itself with the primary, so there is
nothing to approve on member A.

**Observable result:** within a few seconds, member A's monitor shows `MEMBERB` as
`Backup`/`Active`, and member B's monitor shows the same pair from its own side. Run
`setup/verify.sh` to see both views next to each other.

## 5. Add the database on the backup

The mirror is now running, but member B's copy of `MIRRORDATA` is still an ordinary
local database - it is not part of the mirror, so nothing written on the primary
reaches it. Adding it is the last step, and it is the fiddly one: see the *Adding the
database on the backup* section of [README.md](README.md) for what is known about it
and what to expect.

**Observable result to aim for:** `setup/verify.sh` prints a
`mirrored-db=MIRRORDATA` line for member B as well as for member A.

## 6. Prove replication

On member A, in namespace `MIRRORNS`:

```
zn "MIRRORNS"
set ^MirrorProof("written")=$zdt($h,3)
```

Read it on member B (the backup is read-only, so only read there):

```
zn "MIRRORNS"
write $data(^MirrorProof)
```

Allow a few seconds - the backup dejournals asynchronously.

## 7. Fail over

Stop member A:

```bash
docker stop training-mirror-a
```

Watch member B's monitor. It reports the primary as unreachable and **stays the
backup**. This is the point of the exercise: with only two members and no arbiter,
member B cannot tell "A is dead" from "the network to A is broken", and promoting
itself on a guess would risk two primaries writing divergent data.

Promote it deliberately - Mirror Monitor > *Become primary*, or:

```bash
setup/takeover.sh --force     # member A is already stopped
```

**Observable result:** member B's role becomes `Primary`, and the data written in
step 6 is there. Bring A back with `docker start training-mirror-a`; it rejoins as
the backup.
