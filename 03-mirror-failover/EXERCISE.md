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

## What each step actually does

Read this once before starting. The seven steps are not seven small settings - each one changes
what the pair *is*, and knowing which one moves data explains most of what you will see.

| Step | What you do | What happens inside IRIS |
|---|---|---|
| 1 | Enable `%Service_Mirror` on both members | Nothing visible yet. Until this service is on, an instance cannot take part in a mirror at all, and the portal hides the mirror actions - which is why the pages look empty before it |
| 2 | Create mirror `TRAINMIRROR` on A | A writes a mirror definition into its own configuration and makes itself the first failover member. It becomes **primary** at once, because the first member has no partner to synchronise with. No data moves; B knows nothing about any of this |
| 3 | *Add to Mirror* → `MIRRORDATA`, on A | A stamps its own database as belonging to `TRAINMIRROR` and puts an entry into the mirror's **catalogue**: the name, the mirror set and **the directory the database lives in**. From now on every change to it also goes into a mirror journal file. Still nothing on B |
| 4 | *Join Mirror as Failover* on B | B contacts A's ISCAgent on port 2188, registers itself as `MEMBERB`, receives the mirror's configuration **including the catalogue from step 3**, and starts pulling A's mirror journal files. It becomes **backup**. The journals arrive - but B has nowhere to apply them: its own `MIRRORDATA` is a private local database that merely happens to have the same name |
| 5 | On B: delete that local `MIRRORDATA`, recreate it at the catalogue's directory as a mirrored database, recreate `MIRRORNS` | **This is the only step where data actually crosses.** Created at exactly the path the catalogue names, the database is recognised as the mirror's, goes into *download mode*, and its current contents are copied from A. After that, dejournaling can apply what arrived in step 4 and everything that follows. This is also the longest step, because deleting B's copy leaves two things behind that block the recreate |
| 6 | Write a global on A, read it on B | The proof that the whole chain works: A journals the write → the journal file is transferred → B dejournals it into its copy. A few seconds of delay is normal, it is asynchronous |
| 7 | `docker stop training-mirror-a`, then promote B | Stopping the container kills the ISCAgent with it, so B loses both IRIS *and* the agent and cannot tell "A is dead" from "the network to A is broken". It therefore **stays backup** - that is the lesson, not a fault. `BecomePrimary()` is you making the decision instead: B applies everything it has received, opens for writes and becomes primary. `docker start training-mirror-a` brings A back, as the backup |

Where each thing lives: the mirror's configuration is in each member's own `iris.cpf`, the
database files are under `/usr/irissys/mgr/mirrordata/` on both members, and the transferred
journal files appear on B as `/usr/irissys/mgr/journal/MIRROR-TRAINMIRROR-*`.

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
docker exec -it training-mirror-a iris session IRIS -U %SYS      # or training-mirror-b
```

**`-U %SYS` is not optional.** `SYS.Mirror` and the other configuration classes exist only in
`%SYS`; without it the session opens in `USER` and every call below fails with
`<CLASS DOES NOT EXIST> *SYS.Mirror`. `zn "%SYS"` from inside the session fixes it too.

**`docker compose ps` may show a member as `unhealthy` from here on, with the mirror
working.** The image's health check fails whenever the instance is in `alert` state, and a
single severity-2 message puts it there and leaves it there - joining a mirror logs
`Failed to become either Primary or Backup at startup` if the member restarts before the join
settles. What matters is the mirror's own view:

```bash
docker exec training-mirror-b iris list | grep -i mirroring     # expect: Status = Backup
```

If that says `Backup` (or `Primary`) and the status one-liner above reads `Active`, the member
is fine and the `unhealthy` flag is stale. `docker exec training-mirror-b sh -c 'grep -nE ") [23] \[" /usr/irissys/mgr/messages.log | tail'`
shows what raised it.

Then run, on one line:

```
do ##class(SYS.Mirror).GetFailoverMemberStatus(.t,.o) write $listget(t,1)," ",$listget(t,3)," ",$listget(t,4)," / ",$listget(o,1)," ",$listget(o,3)," ",$listget(o,4)
```

## 5. Add the database on the backup

The mirror is now running, but member B's copy of `MIRRORDATA` is still an ordinary
local database - it is not part of the mirror, so nothing written on the primary
reaches it. This is the fiddly step; read it through before clicking. Six sub-steps, in order:

| | |
|---|---|
| 5a | delete B's own `MIRRORDATA` (and `MIRRORNS` with it) |
| 5b | clear the two things the delete leaves behind - the missing directory and the stale mount |
| 5c | create the database again, at the catalogue's directory, as a **mirrored** database |
| 5d | start the download, if the create did not start it |
| 5e | recreate `MIRRORNS` over it |
| 5f | check |

First, ask member B what it thinks is missing. In a session on **B**
(`docker exec -it training-mirror-b iris session IRIS -U %SYS`):

```
set r=##class(%ResultSet).%New("SYS.Mirror:MissingMirroredDatabases") do r.Execute("TRAINMIRROR")
while r.Next() { write !,r.GetData(1) }
```

It answers `:mirror:TRAINMIRROR:MIRRORDATA` - B knows the mirror has a database it does not
have. It knows that because step 3 added `MIRRORDATA` to the mirror on A, and the mirror
propagates its **catalogue** of databases to every member: name, mirror set, and the
directory it lives in on the primary, `/usr/irissys/mgr/mirrordata/`.

That catalogue entry is what makes the rest work, and what makes one mistake fatal: **the
directory you type on B has to be exactly the one in the catalogue.** Accept the wizard's
default and you get `/usr/irissys/mgr/MIRRORDATA/` - a different path, which IRIS does not
recognise as the mirror's database, so it quietly creates an ordinary local one instead.

The obstacle is that `MIRRORDATA` already exists on member B as a local database in the same
directory, and IRIS will not create a database over a leftover `IRIS.DAT`
(`ERROR #20: the file already exists`). So clear it out first.

**5a. Delete B's local `MIRRORDATA`.** **System Administration** → **Configuration** →
**Local Databases** → `MIRRORDATA` → *Delete*. The *Delete Database* page asks for two
confirmations that the printed notes do not mention, and **both have to be ticked**:

| Checkbox on the page | Tick it? | Why |
|---|---|---|
| *Mark namespace(s) to be deleted* → `MIRRORNS` | **yes** | the page says it itself: all associated namespaces have to go before the database can be deleted. `MIRRORNS` is recreated in 5e |
| *Check here if you wish to delete the database file, `/usr/irissys/mgr/mirrordata/IRIS.DAT`* | **yes** | this is the leftover that would otherwise block the recreate. The page notes it only applies when every namespace is marked - so tick the one above first |

Deleting the namespace also deletes any web application attached to it; `MIRRORNS` has none,
so nothing is lost. If the file survives anyway, remove the directory from the host - and any
second directory a hand-made attempt left behind:

```bash
docker exec -u root training-mirror-b rm -rf /usr/irissys/mgr/mirrordata /usr/irissys/mgr/MIRRORDATA
```

**5b. Clear what 5a left behind.** Two leftovers block the create, and they produce the *same*
error - one stack of three statuses, in which only the middle line names a real cause:

```
ERROR #70: *** Error while formatting volume because
ERROR #60: the database must be dismounted to do this
ERROR #73: No such directory
```

First, the **directory**. Deleting the database file in 5a also removed
`/usr/irissys/mgr/mirrordata`, and the portal does not create a directory that you type into the
wizard by hand - it formats a database into one that already exists. So make it, owned by the uid
IRIS runs as:

```bash
docker exec -u root training-mirror-b mkdir -p /usr/irissys/mgr/mirrordata
docker exec -u root training-mirror-b chown 51773:51773 /usr/irissys/mgr/mirrordata
docker exec training-mirror-b ls -la /usr/irissys/mgr/mirrordata
```

The last line must show an **empty** directory owned by `irisowner`. A leftover `IRIS.DAT` in
there blocks the create too; remove it
(`docker exec -u root training-mirror-b rm -f /usr/irissys/mgr/mirrordata/IRIS.DAT`).

Second, the **mount**, which is the one that is easy to miss. B has had `MIRRORDATA` mounted at
that path since it started, read-only because the mirror made it so, and 5a did not dismount it -
so IRIS still holds a mounted database whose files are gone. In the session on B:

```
set d=##class(SYS.Database).%OpenId("/usr/irissys/mgr/mirrordata/") write !,"Mounted=",d.Mounted," ROMounted=",d.ReadOnlyMounted," canmirror=",##class(SYS.Database).CanDatabaseBeMirrored("/usr/irissys/mgr/mirrordata/")
```

`Mounted=1 ROMounted=1 canmirror=0` is the blocked state. **Restart the instance to clear it** -
this is the "restart your instance" of the printed notes, IRIS only, never `docker compose down`:

```bash
docker exec training-mirror-b iris stop IRIS quietly
docker exec training-mirror-b iris start IRIS quietly
```

It also clears the stale `alert` behind an `unhealthy` container. Do not try to dismount by hand:
`SYS.Database.DismountDatabase("/usr/irissys/mgr/mirrordata/")` fails with
`ERROR #5002: ObjectScript error: <PROTECT>Dismount+6^SYS.Database.1` because the mirror holds
that copy read-only.

Then check, in a session on B, that it is clear and that the member has rejoined:

```
write !,"canmirror=",##class(SYS.Database).CanDatabaseBeMirrored("/usr/irissys/mgr/mirrordata/")
do ##class(SYS.Mirror).GetFailoverMemberStatus(.t,.o) write !,$listget(t,1)," ",$listget(t,3)," ",$listget(t,4)," / ",$listget(o,1)," ",$listget(o,3)," ",$listget(o,4)
```

`canmirror=1` and `MEMBERB Backup Active / MEMBERA Primary Active` is the state the wizard needs.
Repeating the `%OpenId` line now raises `<INVALID OREF>`, because after the restart there is no
database object at that path at all - that is the cleared state, not a new fault.

**5c. Create it at the catalogue's path.** *Create New Database* on the same page. The wizard
has two pages, and both matter.

First page:

| Field | Value |
|---|---|
| Name | `MIRRORDATA` |
| Directory | **`/usr/irissys/mgr/mirrordata`** - typed out, lower case, exactly as in the catalogue. Do not accept the default the wizard fills in from the name |

Second page, *Enter details about the database*:

| Field | Value |
|---|---|
| Initial Size (MB) | `1` - leave it. The download brings the primary's content; there is nothing to size in advance |
| Block size, New volume threshold size | `8KB`, `0` - leave both |
| Journal globals? | `Yes`, and greyed out. A mirrored database must be journalled, so the wizard does not let you change it |
| Encrypt database? | `No` |
| **Mirrored database?** | **`Yes`** - this is the field that puts the database in *download mode* instead of creating a plain local one |
| **Mirror DB Name** | **`MIRRORDATA`** - the mirror's own name for the database, the one step 3 gave it on A. It has to match exactly, and it is a separate field from *Name* above |

Then *Finish*.

**Observable result:** the *Local Databases* list has a `MIRRORDATA` row with `TRAINMIRROR` in
the **Mirror** column - that column is empty for every other database in the list. An empty
*Mirror* column here means either *Mirrored database?* was left at `No` or the directory was not
the catalogue's; delete the database (5a), remake the directory (5b) and repeat this step.

**5d. Start the download if it did not start by itself**, in the session on B:

```
set sc=##class(SYS.Mirror).DownloadMirrorDatabase("TRAINMIRROR","MIRRORDATA",0) write !,$system.Status.GetErrorText(sc)
```

`RunBackground=0` makes it wait, so the error text appears instead of having to be hunted for
in `messages.log`. **This call does not create the database** - it only performs the download
for one that is already in download mode. Run it with nothing there, or with an ordinary local
database in the way, and it refuses:

```
ERROR #5001: Existing mirror DB '/usr/irissys/mgr/mirrordata/' is not in Download mode
```

That message means 5c has not been done, or was done at the wrong path.

**5e. Recreate the namespace.** **System Administration** → **Configuration** →
**Namespaces** → *Create New Namespace*: name `MIRRORNS`, globals and routines both
`MIRRORDATA` - the same as it was before 5a, and what step 6 reads. **Leave
*Enable namespace for interoperability productions* unticked**: it imports the Ens schema
globals into the database, which grows it to over 100 MB and writes into a database that is
supposed to be a read-only copy of the primary's.

**5f. Check that it worked**, in the session on B. Two queries and one object:

```
set r=##class(%ResultSet).%New("SYS.Mirror:MirroredDatabaseList") do r.Execute("*","TRAINMIRROR")
while r.Next() { write !,r.GetData(1)," | ",r.GetData(2)," | ",r.GetData(3) }
set r2=##class(%ResultSet).%New("SYS.Mirror:MissingMirroredDatabases") do r2.Execute("TRAINMIRROR")
while r2.Next() { write !,"missing=",r2.GetData(1) }
set d=##class(SYS.Database).%OpenId("/usr/irissys/mgr/mirrordata/") write !,"Mounted=",d.Mounted," RO=",d.ReadOnlyMounted," Download=",d.MirrorDBDownload," ActReq=",d.MirrorActivationRequired," Catchup=",d.MirrorDBCatchup
```

The state to see:

```
MIRRORDATA | /usr/irissys/mgr/mirrordata/ | TRAINMIRROR
Mounted=1 RO=1 Download=0 ActReq=0 Catchup=0
```

- the first query gives B the same single row A has - the same directory, the same mirror set;
- the missing-databases query prints **nothing at all**: the gap step 5 started from is closed;
- `RO=1` is correct, the backup's copy is read-only. `Download=0`, `ActReq=0` and `Catchup=0` mean
  there is no download still running and nothing waiting to be activated or caught up.

If instead `missing=:mirror:TRAINMIRROR:MIRRORDATA` still appears, the database was created
somewhere other than the catalogue's directory - go back to 5a.

### Two ways to be misled here

- **A wrong directory fails silently.** Accepting the wizard's default gives
  `/usr/irissys/mgr/MIRRORDATA/`, and the result is a perfectly ordinary local database that
  looks right in the database list, is writable, and is not in the mirror at all. The only
  symptom is that `MissingMirroredDatabases` still lists `:mirror:TRAINMIRROR:MIRRORDATA`.
- **`SYS.Database` reports the running mount, not what is on disk.** With the directory deleted
  and the database gone from the CPF, `%OpenId("/usr/irissys/mgr/mirrordata/")` on B still
  returned an object with `Mounted=1` and `MirrorSetName=TRAINMIRROR`, which reads as "the
  database is there and in the mirror" when neither is true. After the restart in 5b the same
  call raises `<INVALID OREF>`. So it is a check on this instance's mount table; for the mirror's
  own view use the two `SYS.Mirror` queries.

`SYS.Mirror.AddDatabaseNonPrimary()` is the older API for the same job and is not worth the
trouble: it wants a real mirror journal file counter and fails with *"Journal file #N not found
in mirror journal log"* for any placeholder value. If the database is added but stays behind,
`SYS.Mirror.ActivateMirroredDatabase()` and `SYS.Mirror.CatchupDB()` - or the Mirror Monitor's
*Activate* and *Catchup* actions on B - are the follow-up.

## 6. Prove replication

Write a global on member A:

```bash
docker exec -it training-mirror-a iris session IRIS -U %SYS
```

```
zn "MIRRORNS"
set ^MirrorProof("written")=$zdt($h,3)
halt
```

Read it on member B - the backup is read-only, so only read there:

```bash
docker exec -it training-mirror-b iris session IRIS -U %SYS
```

```
zn "MIRRORNS"
zwrite ^MirrorProof
halt
```

It prints what was written on A:

```
^MirrorProof("written")="2026-09-02 21:44:24"
```

Allow a few seconds - the backup dejournals asynchronously, so an empty answer immediately after
the write means "not yet", not "broken". Do not try to write anything on B: the backup's copy is
mounted read-only, which is correct.

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
docker exec -it training-mirror-b iris session IRIS -U %SYS
```

```
set sc=##class(SYS.Mirror).BecomePrimary()
write $system.Status.GetErrorText(sc)
```

**An empty line is the success.** `GetErrorText()` prints something only for a failure, so a
`BecomePrimary()` that worked writes nothing at all - which reads like the command did nothing.
Check the roles instead, in the same session:

```
do ##class(SYS.Mirror).GetFailoverMemberStatus(.t,.o) write !,$listget(t,1)," ",$listget(t,3)," ",$listget(t,4)," / ",$listget(o,1)," ",$listget(o,3)," ",$listget(o,4)
```

**Observable result:**

```
MEMBERB Primary Active / MEMBERA Backup Down
```

B has taken over, and A is recorded as a backup that is down. The global from step 6 is still
readable - and now writable, because B is the primary:

```
zn "MIRRORNS"
zwrite ^MirrorProof
halt
```

Bring A back with `docker start training-mirror-a`. It rejoins as the backup, and the two portals
now show the roles the other way round from where they started - which is the whole point of one
gateway per member.

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
