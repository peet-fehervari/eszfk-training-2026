# Stack 3 - mirror / failover pair

Two IRIS 2026.1 failover members, each with its own Web Gateway. The stack comes up
prepared but with **no mirror configured**: creating it is the exercise, see
[EXERCISE.md](EXERCISE.md).

## Ports

| Service | Container | Superserver | Portal | ISCAgent |
|---|---|---|---|---|
| `mirror-a` | `training-mirror-a` | 63972 | 63773 | 63188 |
| `mirror-b` | `training-mirror-b` | 63973 | 63774 | 63189 |

Portal: `http://localhost:63773/csp/sys/UtilHome.csp` (member A) and `...:63774/...`
(member B), `SuperUser` / `SYS`.

Each gateway is bound to one member deliberately, so after a takeover the two portals
disagree about who is primary - which is how the role change becomes visible.

## Run

```bash
docker compose up -d
docker compose logs mirror-a | grep -i "LMF Info"   # must show a licensed instance
```

There are no scripts here: building the mirror is the exercise, done in the portal on
both members. [EXERCISE.md](EXERCISE.md) has the steps, and the ObjectScript one-liners
to check the roles from a session on either member.

Reset to a clean, unconfigured state:

```bash
docker compose down -v && docker compose up -d
```

## What is prepared

- Both members licensed from the shared key store and healthy.
- ISCAgent listening on 2188 in both containers. `iris-main` starts it by default -
  there is no prerequisite to satisfy here, contrary to what the mirroring
  documentation implies for a bare-metal install.
- `MIRRORDATA` database (journalled) and `MIRRORNS` namespace over it on **both**
  members, both empty. A real mirror is seeded from a backup of the primary; two
  empty copies make the exercise quick.

Left undone on purpose: `%Service_Mirror` is disabled, no mirror set exists, neither
member has joined anything.

## No arbiter, no virtual IP

**No arbiter**, and none is needed: the specification asks for two failover members, and the
mirror runs without one. The consequence is the interesting part. Stop member A's whole
container - which takes its ISCAgent with it - and member B cannot distinguish a dead partner
from a broken network, so it stays the backup. Takeover is then an operator decision, made in
the portal on member B or with `SYS.Mirror.BecomePrimary()`. (Stopping only IRIS with
`iris stop` leaves the agent answering, which is a different case; [EXERCISE.md](EXERCISE.md)
step 7 says which to use.)

**No virtual IP** because a mirror VIP requires the members to share a subnet on which
an interface can be moved from one host to the other. A Docker bridge network does not
provide that. Clients connect to a member directly, or through that member's own
gateway. This is a limitation of the container environment, not something to fix in
the compose file.

## Adding the database on the backup

Status: **done and verified end to end on a live pair.** Every step of
[EXERCISE.md](EXERCISE.md) has been run, including replication of real data and the takeover: a
global written in `MIRRORNS` on member A was read back on member B, and after
`docker stop training-mirror-a` plus `SYS.Mirror.BecomePrimary()` member B reported
`MEMBERB Primary Active` / `MEMBERA Backup Down` with that global still there.

The route is step 5 of [EXERCISE.md](EXERCISE.md): delete B's own copy, clear the leftovers,
recreate the database at the catalogue's path with *Mirrored database? Yes*, recreate the
namespace. It needs no `AddDatabaseNonPrimary` and no journal point. What the live pair
established along the way - the traps are all in the details, which is why step 5 is long:

- **Adding the database on A propagates a catalogue entry to B.** After step 3, A's
  `SYS.Mirror:MirroredDatabaseList` holds
  `MIRRORDATA | /usr/irissys/mgr/mirrordata/ | TRAINMIRROR`, and B's
  `SYS.Mirror:MissingMirroredDatabases` returns `:mirror:TRAINMIRROR:MIRRORDATA`. B knows the
  name, the mirror set **and the directory**.
- **The directory decides everything on B.** Creating the database there at the catalogue's
  path is what makes IRIS treat it as the mirror's database. The *Create New Database* wizard
  defaults *Directory* to the database name in **upper case**, and accepting that gave
  `/usr/irissys/mgr/MIRRORDATA/`: an ordinary writable local database, `MirrorSetName=""`,
  looking entirely normal in the database list, with `MissingMirroredDatabases` still
  reporting the database as absent. That is the trap.
- **Deleting the database in the portal does not dismount the one at the catalogue's path.**
  Measured on B: after the delete and an `rm -rf` of the directory,
  `SYS.Database.%OpenId("/usr/irissys/mgr/mirrordata/")` still reported `Mounted=1`,
  `ReadOnlyMounted=1` (the mirror mounts the backup's copy read-only) and
  `CanDatabaseBeMirrored()` returned `0`, while `messages.log` showed a dismount only for the
  *other*, hand-made `/usr/irissys/mgr/MIRRORDATA/`. The wizard then fails with
  `ERROR #70: *** Error while formatting volume because ERROR #60: the database must be dismounted
  to do this ERROR #73: No such directory` - three statuses of which only `#60` names the cause,
  and `#73` points at the mounted database's missing files rather than at the directory just
  created. An `iris stop` / `iris start` on the member clears it;
  `SYS.Database.DismountDatabase()` does not - it fails with
  `<PROTECT>Dismount+6^SYS.Database.1`, since the mirror holds the backup's copy read-only.
- **The wizard's second page is where the mirror is actually declared.** *Mirrored database?*
  must be `Yes` and *Mirror DB Name* must be the mirror's name for the database (`MIRRORDATA`,
  a field of its own, not derived from *Name*). *Journal globals?* is forced to `Yes` and greyed
  out once mirroring is on. With the right directory and *Mirrored database?* left at `No` the
  result is the same ordinary local database as above.
- **`SYS.Mirror.DownloadMirrorDatabase(MirrorSetName, MirrorDBName, RunBackground)` does not
  create anything.** It performs the download for a database that is already in *download
  mode*, which is the state the portal puts it in when created at the catalogue's path. Called
  with nothing there it fails with
  `ERROR #5001: Existing mirror DB '/usr/irissys/mgr/mirrordata/' is not in Download mode`.
- **`SYS.Database` reports the mount table, not the disk.** `%OpenId("/usr/irissys/mgr/mirrordata/")`
  on B returned an object with `Mounted=1`, `ReadOnlyMounted=1`, `MirrorSetName=TRAINMIRROR` and
  `MirrorDBName=MIRRORDATA` while the directory was deleted from disk and the database gone from
  the CPF - it was reporting the mount left over from instance start, which reads as "present and
  mirrored" when neither is true. After an `iris stop` / `iris start` the same call raises
  `<INVALID OREF>`. A bogus directory returns nothing either way, so it looks like a real check on
  the database. It is not.
- `Config.Databases:MirrorDatabaseList`, which this README used to recommend, returns nothing
  on the backup even when the mirror is healthy. `SYS.Mirror:MirroredDatabaseList` and
  `SYS.Mirror:MissingMirroredDatabases` are the queries to use.

- **The success state on B**, once step 5 is done: `SYS.Mirror:MirroredDatabaseList` returns the
  same single row as on A, `SYS.Mirror:MissingMirroredDatabases` returns nothing, and
  `SYS.Database.%OpenId("/usr/irissys/mgr/mirrordata/")` reports `Mounted=1`,
  `ReadOnlyMounted=1`, `MirrorDBDownload=0`, `MirrorActivationRequired=0`, `MirrorDBCatchup=0`.
  Read-only is correct there - it is the backup's copy.

Two APIs that look like the answer and are not needed:

- `SYS.Mirror.AddDatabaseNonPrimary(Directory, MirrorSetName, MirrorDBName, JrnPointMirfcnt,
  JrnPointOffset, DBInfo, RunCatchupDB, enableJournalOK)` is the older backup-side call. It wants
  a real mirror journal file counter: `0,0` fails with *"Journal file #0 not found in mirror
  journal log"* and `1,0` the same for #1. The portal route in step 5 needs none of this.
- `SYS.Mirror.ActivateMirroredDatabase(Directory)` and
  `SYS.Mirror.CatchupDB(DBList, JournalLocation, &DBErrList)` - or the Mirror Monitor's
  *Activate* and *Catchup* - are only for a database that is added but stays inactive or behind.
  On this pair the download left nothing to do.

One design choice worth knowing: `cpf/member-b.cpf` creates `MIRRORDATA` on member B at the same
directory as on A, so step 5 has to delete it before it can be recreated as the mirror's copy.
Dropping that `CreateDatabase` line would let step 5 start straight at the create, at the cost of
the two members no longer coming up symmetrical - and the delete is itself instructive, since it
is where the mount and directory leftovers above show up. It stays.
