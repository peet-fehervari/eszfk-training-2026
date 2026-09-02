# Exercise - set up a two-member mirror and fail over

The stack starts with both members licensed, healthy and journalled, each with an
empty `MIRRORDATA` database and a `MIRRORNS` namespace over it. Their ISCAgents are
already listening on 2188 - `iris-main` starts the agent by default, so there is
nothing to do for that prerequisite.

Everything below is deliberately left undone. Do it in the portal - there are no
scripts for it; doing it is the exercise. To start over, `docker compose down -v` and
up again.

| Member | Portal | Role after setup |
|---|---|---|
| A | http://localhost:63773/csp/sys/UtilHome.csp | primary |
| B | http://localhost:63774/csp/sys/UtilHome.csp | backup |

Log in as `SuperUser` / `SYS`. Each portal is bound to one member only, so the two
show the mirror from different sides - that is what makes the takeover visible.

There is no arbiter and no virtual IP in this stack. Both omissions are deliberate;
see the header of `docker-compose.yml`.

## 1. Enable the mirror service on both members

**System Administration** → **Security** → **Services** → `%Service_Mirror` → tick
*Service Enabled*.

It is off in a fresh instance. Do it on **both** members - the mirror pages stay
mostly empty until it is on.

**Observable result:** **System Administration** → **Configuration** → **Mirror Settings**
now offers *Create Mirror* and *Join Mirror as Failover*.

## 2. Create the mirror set on member A

**System Administration** → **Configuration** → **Mirror Settings** → *Create Mirror*.

- Mirror name: `TRAINMIRROR`
- Member name: `MEMBERA`
- Use SSL/TLS: **off**. A mirror normally requires TLS; it is off here so the
  exercise is about mirroring rather than about certificates.
- Arbiter, virtual IP: leave empty.
- Agent address / mirror address / superserver address: `mirror-a`. Use the **service
  name**, not `localhost` - member B resolves this name on the stack network, and
  `localhost` there would mean member B itself.

**Observable result:** the *Mirror Monitor* - **System Operation** → **Mirror Monitor**, not
under *Configuration*; once a mirror exists the portal home page links to it directly - is
headed *This system is a failover member in mirror TRAINMIRROR*, and shows one member:

| Panel | What it says with only member A in the mirror |
|---|---|
| Mirror Failover Member Information | `MEMBERA`, superserver and mirror private address `mirror-a`; the *Other Failover Member* column is `n/a` |
| Mirror Member Status | one row: `MEMBERA` \| Failover \| **Primary** \| Journal Transfer `N/A` \| Dejournaling `N/A` |
| Mirrored Databases | `No Results` |

The *Status* column holds the **role**, so `Primary` is the whole answer there - the monitor
never prints `Active`. That word belongs to the `SYS.Mirror` API used in step 4, which reports
role and status as two values (`Primary Active`). Journal Transfer and Dejournaling are `N/A`
because there is no partner to transfer to yet, and the database list stays empty until step 3.

**The *Arbiter Connection Status* panel reads *Arbiter not configured* and *This member is not
connected to the arbiter*. Nothing is wrong.** This stack has no arbiter on purpose - see
[README.md](README.md) and the compose file header. The *Failover Mode* on that panel is
therefore `Agent Controlled`, which is exactly why the takeover in step 7 has to be an operator
decision.

## 3. Add the database to the mirror on member A

**System Administration** → **Configuration** → **Local Databases** → *Add to Mirror*, and
tick `MIRRORDATA`.

*Add to Mirror* is a button in the page's toolbar, next to *Create New Database*, and it only
appears once this instance is a member of a mirror - so after step 2, not before.

**Not in the Mirror Monitor.** The monitor's *Mount* / *Activate* / *Catchup* / *Remove* actions
operate on databases that are **already** in the mirror, so while nothing has been added their
lists are empty: choosing *Mount* → *Go* there opens a dialog that says `No Results`. That is
the empty list, not a failure.

**Observable result:** `MIRRORDATA` is listed as a mirrored database of
`TRAINMIRROR`, and its journalling stays on. The monitor's *Mirrored Databases* panel, which
read `No Results` a moment ago, now has a row for it.

## 4. Join member B as the second failover member

On member B's portal: **System Administration** → **Configuration** → **Mirror Settings** →
*Join Mirror as Failover*.

- Mirror name: `TRAINMIRROR`
- Agent address of the primary: `mirror-a`, port `2188`
- Instance name on the primary: `IRIS`
- Member name: `MEMBERB`
- Its own agent / mirror / superserver address: `mirror-b`

With TLS off the joining member registers itself with the primary, so there is
nothing to approve on member A.

**Observable result:** within a few seconds, member A's *Mirror Member Status* has a second
row, `MEMBERB` | Failover | **Backup**, the *Other Failover Member* column fills in, and the
`N/A`s in *Journal Transfer* and *Dejournaling* turn into live values now that there is a
partner to transfer to. Member B's monitor shows the same pair from its own side.

The API is the exact check, and it is the one place the word `Active` appears - it reports role
and status as two separate values, so a healthy pair reads `MEMBERA Primary Active` /
`MEMBERB Backup Active`. From a session on either member:

```
do ##class(SYS.Mirror).GetFailoverMemberStatus(.t,.o) write $listget(t,1)," ",$listget(t,3)," / ",$listget(o,1)," ",$listget(o,3)
```

## 5. Add the database on the backup

The mirror is now running, but member B's copy of `MIRRORDATA` is still an ordinary
local database - it is not part of the mirror, so nothing written on the primary
reaches it. Adding it is the last step, and it is the fiddly one: see the *Adding the
database on the backup* section of [README.md](README.md) for what is known about it
and what to expect.

**Observable result to aim for:** member B lists `MIRRORDATA` as a mirrored database,
the same as member A does. In a session on either member:

```
set r=##class(%ResultSet).%New("Config.Databases:MirrorDatabaseList") do r.Execute("*")
while r.Next() { write r.GetData(1)," ",r.GetData(3),! }
```

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

Promote it deliberately - in the *Mirror Monitor*, *Become primary*, or from a session on
member B:

```
set sc=##class(SYS.Mirror).BecomePrimary() write $system.Status.GetErrorText(sc)
```

**Observable result:** member B's role becomes `Primary`, and the data written in
step 6 is there. Bring A back with `docker start training-mirror-a`; it rejoins as
the backup.
