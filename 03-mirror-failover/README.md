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
setup/verify.sh                                     # read-only, safe at any stage
```

Scripted equivalent of the exercise:

```bash
setup/01-create-mirror.sh    # member A: enable service, create TRAINMIRROR, add DB
setup/02-join-mirror.sh      # member B: enable service, join as MEMBERB
setup/verify.sh
setup/takeover.sh            # stop member A, promote member B
```

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

**No arbiter** because the specification asks for two failover members. The
consequence is the interesting part: a member that loses contact with its partner
cannot distinguish a dead partner from a broken network, so it never promotes itself.
Takeover is an operator decision - `setup/takeover.sh`.

**No virtual IP** because a mirror VIP requires the members to share a subnet on which
an interface can be moved from one host to the other. A Docker bridge network does not
provide that. Clients connect to a member directly, or through that member's own
gateway. This is a limitation of the container environment, not something to fix in
the compose file.

## Adding the database on the backup

Status: **not solved in this repository.** Steps 1-4 of the exercise were run and
verified on the live pair; this step was not. It is the one thing left to work out.

What was established:

- After the join, member A reports `MEMBERA Primary Active` / `MEMBERB Backup Active`
  and member B reports the mirror image of that, so the mirror itself is healthy.
- `SYS.Mirror.AddDatabase("/usr/irissys/mgr/mirrordata/","MIRRORDATA",1)` on member A
  succeeds, and `Config.Databases:MirrorDatabaseList` on member A then lists
  `MIRRORDATA|TRAINMIRROR|/usr/irissys/mgr/mirrordata/`.
- The same query on member B returns **nothing**: its copy is an ordinary local
  database, so a global written in `MIRRORNS` on the primary never appears there.
  Journal transfer itself does work - member B's journal directory contains
  `MIRROR-TRAINMIRROR-*` files.
- The backup-side call is
  `SYS.Mirror.AddDatabaseNonPrimary(Directory, MirrorSetName, MirrorDBName,
  JrnPointMirfcnt, JrnPointOffset, DBInfo, RunCatchupDB, enableJournalOK)`.
  Called with journal point `0,0` it fails with *"Journal file #0 not found in mirror
  journal log"*, and with `1,0` with the same message for #1 - so the journal point
  has to be a real mirror journal file counter, not a placeholder.

Where to look next:

- `SYS.Mirror:JournalList(MirrorName)` and `SYS.Mirror:MissingMirroredDatabases(MirrorSetName)`
  are queries on a live instance; the second is what the portal's backup-side page
  lists, and it should give the values the call wants.
- `SYS.Mirror.ActivateMirroredDatabase(Directory)` and
  `SYS.Mirror.CatchupDB(DBList, JournalLocation, &DBErrList)` are the follow-up
  operations if the database is added but stays inactive or behind.
- The portal route (Mirror Monitor on member B) fills these in from the mirror's own
  state, so doing it once in the UI and reading back the resulting configuration is
  probably faster than deriving the arguments.

Until this is done, the exercise stops being verifiable at step 5: the roles and the
takeover are demonstrable, replication of actual data is not.
