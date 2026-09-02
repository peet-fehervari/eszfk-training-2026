# Exercise - split the code from the data over ECP

Everything needed to follow this document is in it - the commands to start the stack, the
commands to open a session, and the portal steps. Nothing else has to be read first.

## Before you start

The stack creates everything this exercise needs, so there is no preparation script to run
for it. From the `02-code-data-ecp` directory:

```bash
docker compose up -d
docker compose ps                        # wait until all four containers are healthy
docker compose logs code | grep -i "LMF Info"    # expect: Licensed for N cores
```

On Windows, in PowerShell:

```powershell
docker compose up -d
docker compose ps
docker compose logs code | Select-String "LMF Info"
```

**Only if you are doing the course's *Enterprise Cache Protocol* module here** rather than
this exercise on its own: that module works on the Phonebook databases, which this stack does
not ship, so prepare both instances first. From the same directory:

```bash
cd ../common/course
./prepare-instance.sh training-ecp-code training-ecp-data
./install-phonebook.sh training-ecp-data
./install-phonebook.sh training-ecp-code
cd ../../02-code-data-ecp
```

On Windows, in PowerShell:

```powershell
cd ..\common\course
.\prepare-instance.ps1 training-ecp-code training-ecp-data
.\install-phonebook.ps1 training-ecp-data
.\install-phonebook.ps1 training-ecp-code
cd ..\..\02-code-data-ecp
```

`prepare-instance` creates the course directories and the OS accounts; it is idempotent and
prints `OK` / `FAILED` per prerequisite, so it is also the check, and it has to be re-run
after a container recreate. The module's own step-by-step deviations are in
[../common/course/COURSE-NOTES.md](../common/course/COURSE-NOTES.md) under *Enterprise Cache
Protocol*; the steps below are the same wiring with this stack's own names.

## Starting state

Everything is in place except the connection between the two instances.

The two portals, `SuperUser` / `SYS` - the full path is required, the bare host and
port returns HTTP 404:

| Instance | Management Portal |
|---|---|
| code | http://localhost:62773/csp/sys/UtilHome.csp |
| data | http://localhost:62774/csp/sys/UtilHome.csp |

| | code instance (portal 62773) | data instance (portal 62774) |
|---|---|---|
| Databases | `TRAINCODE` | `TRAINDATA` |
| Namespaces | `TRAINING` → globals *and* routines in `TRAINCODE` | `DATA` → `TRAINDATA` |
| ECP service | n/a | **disabled** |

So the `TRAINING` namespace on the code instance currently keeps everything local.

## Goal

Move only the **data** to the other instance, leaving the code where it is:

| | code instance | data instance |
|---|---|---|
| `TRAINING` routines | `TRAINCODE`, local | - |
| `TRAINING` globals | `REMOTEDATA` → remote | physically in `TRAINDATA` |

Classes, routines and utilities are then written, compiled and executed on the code
instance, while every global they touch is stored on the data instance.

## Steps

### 1. Allow the data instance to serve its database (on the **data** instance)

Data portal (62774) → **System Administration** → **Security** → **Services** →
`%Service_ECP`. Tick *Service Enabled*, save.

ECP is disabled by default on 2026.1. Skipping this step is the most common cause
of the next step appearing to work and then failing at first use.

### 2. Tell the code instance where the data server is (on the **code** instance)

Code portal (62773) → **System Administration** → **Configuration** → **ECP Settings** →
**ECP Data Servers** → *Add Data Server*:

| Field | Value |
|---|---|
| Server Name | `DATA` |
| Host DNS Name or IP Address | `data` |
| IP Port | `1972` |

*ECP Settings* and *ECP Data Servers* are two different pages. The first has one link per
direction - this system as a data server, this system as an application server - and the list
you want is behind the second.

`data` is the Docker service name on the stack network, and `1972` is the port
**inside** the container. The published host port 62873 is for tools running on
your machine, not for container-to-container traffic - using it here fails.

The new row appears as *Not Connected*, with `0.0.0.0` in the *IP Address* column.
That is the correct state, not a failure - see the next step.

### 3. Bring the connection up (on the **code** instance)

Same page, in the `DATA` row: *Change Status* → **Normal**.

| | Before | After |
|---|---|---|
| Status | `Not Connected` | `Normal` |
| IP Address | `0.0.0.0` | the data container's address, e.g. `172.26.0.2` |

**Nothing was wrong before this step.** ECP establishes the connection on first use,
so a freshly added data server sits at *Not Connected* and its host name has not been
resolved yet - which is why the address column reads `0.0.0.0`. This step is what
connects it. Accessing a remote database on the server (step 4) would also connect it,
but then a mistake in step 1 surfaces there instead of here.

To check it from the other side, the data instance's ECP Settings page lists the
application server under *This System as an ECP Data Server*.

If the status will not stay at *Normal*, step 1 was skipped: the data instance is not
serving.

### 4. Mount the remote database (on the **code** instance)

**System Administration** → **Configuration** → **Remote Databases** →
*Create Remote Database*:

| Field | Value |
|---|---|
| Server | `DATA` |
| Directory | `/usr/irissys/mgr/traindata/` |
| Database Name | `REMOTEDATA` |

**Not on the *Local Databases* page.** *Create New Database* there builds a local database and
has no server field at all; a remote database has its own page and its own button.

Fill the fields in that order: *Directory* is a dropdown that the portal populates by asking
the data server what it has, so it stays empty until *Server* is set and the connection from
step 3 is up. The path is the one that exists **on the data instance**.

**Do not double-click a row in the list on that page.** In 2026.1 the row's double-click
handler calls a method the page does not have, and the portal answers with a red
`ZEN EXCEPTION ... zenPage.editItem is not a function`. It is a portal bug, nothing is broken
and nothing was saved - dismiss it and use the buttons.

### 5. Point the namespace's data at it (on the **code** instance)

**System Administration** → **Configuration** → **Namespaces** → `TRAINING` → change the
**global** database to `REMOTEDATA`. Leave the routine database as `TRAINCODE`.

That single asymmetry is the whole architecture.

### 6. Prove it

Open a session on the code instance - this is what "open a Terminal session" means here:

```bash
docker exec -it training-ecp-code iris session IRIS -U %SYS
```

and write a global:

```objectscript
zn "TRAINING"
set ^MyProof("hello")="from the code instance"
halt
```

Then read it on the data instance:

```bash
docker exec -it training-ecp-data iris session IRIS -U %SYS
```

```objectscript
zn "DATA"
zwrite ^MyProof
halt
```

**Expect a delay.** ECP does not push every write to the data server immediately;
modified blocks sit in the client cache until they are flushed. Reading the data
instance straight away can show nothing, which looks like a broken setup but is
normal ECP behaviour. Wait a few seconds and read it again.

### 7. Optional - show that the code really did stay put

Create a class in the `TRAINING` namespace on the code instance, compile it, and
store some data through it. Then look for that class on the data instance: it is not
there, only its data is. Code and data are genuinely on different instances.

## Reset

To do the exercise again from scratch:

```bash
docker compose down -v && docker compose up -d
```

On Windows, in PowerShell - two lines, because Windows PowerShell has no `&&`:

```powershell
docker compose down -v
docker compose up -d
```

If you ran the two course scripts above, run them again afterwards: `down -v` discards the
Phonebook with everything else.
