# Exercise - split the code from the data over ECP

## Starting state

`docker compose up -d` gives you two licensed instances. Everything is in place
except the connection between them:

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

Portal 62774 → System Administration → Security → Services → `%Service_ECP`
(page `%CSP.UI.Portal.Services`). Tick *Service Enabled*, save.

ECP is disabled by default on 2026.1. Skipping this step is the most common cause
of the next step appearing to work and then failing at first use.

### 2. Tell the code instance where the data server is (on the **code** instance)

Portal 62773 → System Administration → Configuration → Connectivity →
ECP Settings (page `%CSP.UI.Portal.ECPDataServers`) → *Add Data Server*:

| Field | Value |
|---|---|
| Server Name | `DATA` |
| Host DNS Name or IP Address | `data` |
| IP Port | `1972` |

`data` is the Docker service name on the stack network, and `1972` is the port
**inside** the container. The published host port 62973 is for tools running on
your machine, not for container-to-container traffic - using it here fails.

The connection status should become *Normal*. If it stays *Not Connected*, step 1
was skipped.

### 3. Mount the remote database (on the **code** instance)

System Administration → Configuration → System Configuration → Local Databases
(page `%CSP.UI.Portal.Databases`) → *Create New Database*, and choose a **remote**
database (dialog `%CSP.UI.Portal.Dialog.RemoteDatabase`):

| Field | Value |
|---|---|
| Name | `REMOTEDATA` |
| Server | `DATA` |
| Directory | `/usr/irissys/mgr/traindata/` |

The directory is the path as it exists **on the data instance**.

### 4. Point the namespace's data at it (on the **code** instance)

System Administration → Configuration → System Configuration → Namespaces
(page `%CSP.UI.Portal.Namespaces`) → `TRAINING` → change the **global** database to
`REMOTEDATA`. Leave the routine database as `TRAINCODE`.

That single asymmetry is the whole architecture.

### 5. Prove it

On the code instance:

```objectscript
zn "TRAINING"
set ^MyProof("hello")="from the code instance"
```

then on the data instance:

```objectscript
zn "DATA"
zwrite ^MyProof
```

**Expect a delay.** ECP does not push every write to the data server immediately;
modified blocks sit in the client cache until they are flushed. Reading the data
instance straight away can show nothing, which looks like a broken setup but is
normal ECP behaviour. Wait a few seconds and read it again.

### 6. Optional - show that the code really did stay put

Create a class in the `TRAINING` namespace on the code instance, compile it, and
store some data through it. Then look for that class on the data instance: it is not
there, only its data is. Code and data are genuinely on different instances.

## Reset

To do the exercise again from scratch:

```bash
docker compose down -v && docker compose up -d
```
