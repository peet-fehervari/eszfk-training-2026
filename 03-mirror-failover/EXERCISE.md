# Exercise - set up a two-member mirror and fail over

Everything needed to follow this document is in it - the commands to start the stack, the
commands to open a session, and the portal steps. Nothing else has to be read first.

The stack starts with both members licensed, healthy and journalled, each with an
empty `MIRRORDATA` database and a `MIRRORNS` namespace over it. Their ISCAgents are
already listening on 2188 - `iris-main` starts the agent by default, so there is
nothing to do for that prerequisite.

Everything below is deliberately left undone. Do it in the portal - there are no
scripts for it; doing it is the exercise.

| Member | Portal | Role after setup |
|---|---|---|
| A | http://localhost:63773/csp/sys/UtilHome.csp | primary |
| B | http://localhost:63774/csp/sys/UtilHome.csp | backup |

Log in as `SuperUser` / `SYS`. Each portal is bound to one member only, so the two
show the mirror from different sides - that is what makes the takeover visible.

## No arbiter is needed, and there is none

**Do not configure an arbiter, and do not start one.** A two-member mirror runs without it;
every step below works with the *Use Arbiter* box left unticked, and the mirror reports
itself healthy that way. Where it shows up:

| Where | What you will see |
|---|---|
| Step 2, *Create Mirror* | leave *Use Arbiter* **off** and the arbiter fields empty |
| The Mirror Monitor, on both members | *Arbiter not configured*, *This member is not connected to the arbiter*, *Failover Mode: Agent Controlled* - **all three are correct, nothing is wrong** |
| Step 7, the takeover | the backup does not promote itself; you promote it |

That last line is the reason the arbiter is left out. With two members and no arbiter, a
member that has lost contact with its partner cannot tell "the partner is dead" from "the
network to the partner is broken", so promoting itself on a guess would risk two primaries
writing divergent data. The takeover is therefore an operator decision - which is the point
of step 7, and the thing this stack was built to show.

There is also **no virtual IP**, and there cannot be one: a mirror VIP needs the members to
share a subnet on which an interface can be moved from one host to the other, and a Docker
bridge network does not provide that. Connect to whichever member you mean through its own
portal.

## Before you start

The stack creates everything this exercise needs, so there is no preparation script to run
for it. From the `03-mirror-failover` directory:

```bash
docker compose up -d
docker compose ps                          # wait until all four containers are healthy
docker compose logs mirror-a | grep -i "LMF Info"    # expect: Licensed for N cores
```

On Windows, in PowerShell:

```powershell
docker compose up -d
docker compose ps
docker compose logs mirror-a | Select-String "LMF Info"
```

**Only if you are doing the course's *Mirroring* module here** rather than this exercise on
its own: that module works on the Phonebook databases, which this stack does not ship, so
prepare both members first. From the same directory:

```bash
cd ../common/course
./prepare-instance.sh training-mirror-a training-mirror-b
./install-phonebook.sh training-mirror-a
./install-phonebook.sh training-mirror-b
cd ../../03-mirror-failover
```

On Windows, in PowerShell:

```powershell
cd ..\common\course
.\prepare-instance.ps1 training-mirror-a training-mirror-b
.\install-phonebook.ps1 training-mirror-a
.\install-phonebook.ps1 training-mirror-b
cd ..\..\03-mirror-failover
```

`prepare-instance` creates the course directories and the OS accounts on both members; it is
idempotent and prints `OK` / `FAILED` per prerequisite, so it is also the check, and it has to
be re-run after a container recreate. The module's own step-by-step deviations are in
[../common/course/COURSE-NOTES.md](../common/course/COURSE-NOTES.md) under *Mirroring*; the
steps below are the same mirror with this stack's own names.

To start over at any point, see [Reset](#reset) at the end.

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
- Use Arbiter: **off**, arbiter fields empty - see *No arbiter is needed* above.
- Use Virtual IP: **off**, fields empty.
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

**The *Arbiter Connection Status* panel reads *Arbiter not configured*, *This member is not
connected to the arbiter* and *Failover Mode: Agent Controlled*. All three are correct and
nothing is wrong** - there is no arbiter here on purpose, as stated above. Do not go looking
for one to configure.

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
`MEMBERB Backup Active`. Open a session - this is what "open a Terminal session" means here -
on either member:

```bash
docker exec -it training-mirror-a iris session IRIS      # or training-mirror-b
```

and run, on one line:

```
do ##class(SYS.Mirror).GetFailoverMemberStatus(.t,.o) write $listget(t,1)," ",$listget(t,3)," ",$listget(t,4)," / ",$listget(o,1)," ",$listget(o,3)," ",$listget(o,4)
```

## 5. Add the database on the backup

The mirror is now running, but member B's copy of `MIRRORDATA` is still an ordinary
local database - it is not part of the mirror, so nothing written on the primary
reaches it. This is the fiddly step, and the only one that has **not** been verified on this
pair; expect to have to work at it.

Take the portal route, on **member B**: from 2025.1 a non-primary member downloads a mirrored
database from the primary by itself, so creating the database with *Mirrored Database: Yes*
is enough - no journal point to work out.

The obstacle is that `MIRRORDATA` already exists on member B as a local database in the same
directory, and IRIS will not create a database over a leftover `IRIS.DAT`
(`ERROR #20: the file already exists`). So delete it first: **System Administration** →
**Configuration** → **Local Databases** → `MIRRORDATA` → *Delete*, and remove what is left
behind on disk -

```bash
docker exec -u root training-mirror-b rm -rf /usr/irissys/mgr/mirrordata
```

- then *Create New Database* on the same page, name `MIRRORDATA`, directory
`/usr/irissys/mgr/mirrordata`, **Mirrored Database: Yes**, and point the `MIRRORNS` namespace
back at it if the delete cleared it.

The `SYS.Mirror.AddDatabaseNonPrimary()` API does the same thing without the portal, but it
wants a real mirror journal file counter and fails with *"Journal file #N not found in mirror
journal log"* for any placeholder value, so the portal is the shorter way. If the database is
added but stays behind, the Mirror Monitor's *Activate* and *Catchup* actions on member B are
the follow-up.

**Observable result to aim for:** member B lists `MIRRORDATA` as a mirrored database,
the same as member A does. In a session on either member
(`docker exec -it training-mirror-b iris session IRIS`), one line each:

```
set r=##class(%ResultSet).%New("Config.Databases:MirrorDatabaseList") do r.Execute("*")
while r.Next() { write r.GetData(1)," ",r.GetData(3),! }
```

## 6. Prove replication

Write a global on member A:

```bash
docker exec -it training-mirror-a iris session IRIS
```

```
zn "MIRRORNS"
set ^MirrorProof("written")=$zdt($h,3)
halt
```

Read it on member B - the backup is read-only, so only read there:

```bash
docker exec -it training-mirror-b iris session IRIS
```

```
zn "MIRRORNS"
write $data(^MirrorProof)
halt
```

Allow a few seconds - the backup dejournals asynchronously.

## 7. Fail over

Stop member A - the whole **container**, not just IRIS:

```bash
docker stop training-mirror-a
```

That is deliberate. The container also runs the ISCAgent on 2188, and stopping the container
takes the agent with it, which is what leaves member B with no way to find out what happened to
its partner. If you only stop IRIS (`docker exec training-mirror-a iris stop IRIS quietly`) the
agent stays up and answers, and IRIS can then decide by itself - so use `docker stop` for this
step.

Watch member B's monitor. It reports the primary as unreachable and **stays the
backup**. This is the point of the exercise: with only two members and no arbiter,
member B cannot tell "A is dead" from "the network to A is broken", and promoting
itself on a guess would risk two primaries writing divergent data.

Promote it deliberately - in the *Mirror Monitor* on member B, or from a session on it:

```bash
docker exec -it training-mirror-b iris session IRIS
```

```
set sc=##class(SYS.Mirror).BecomePrimary() write $system.Status.GetErrorText(sc)
halt
```

**Observable result:** member B's role becomes `Primary`, and the data written in
step 6 is there. Bring A back with `docker start training-mirror-a`; it rejoins as
the backup.

## Reset

To do the exercise again from scratch - this discards both instances' data, including the
mirror configuration:

```bash
docker compose down -v && docker compose up -d
```

On Windows, in PowerShell - two lines, because Windows PowerShell has no `&&`:

```powershell
docker compose down -v
docker compose up -d
```

If you ran the two course scripts from *Before you start*, run them again afterwards:
`down -v` discards the Phonebook with everything else, and a container recreate loses the OS
accounts in any case.
