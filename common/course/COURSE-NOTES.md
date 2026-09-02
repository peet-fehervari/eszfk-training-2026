# Course notes - where this environment differs from the printed exercises

The exercise notes were written for an IRIS installed by hand on Windows or on an Ubuntu
VM. Here IRIS runs in a container that is already installed, licensed and started. Almost
every step works unchanged; this file lists, module by module, the places where a path, a
port, a service name or a command is different, one line each.

Page numbers are the printed exercise document's. Read the two rules below first - they
answer most of the differences on their own.

## The two rules that cover everything else

**1. "Open a Terminal session" means one `docker exec`.** Instead of PuTTY, the
InterSystems Launcher or `irissession TRAINING`, from PowerShell or a terminal on your own
machine:

```
docker exec -it training-health iris session IRIS -U %SYS
```

The instance is called **`IRIS`**, not `TRAINING`, and it lives in **`/usr/irissys`**, not
in `C:\InterSystems\training`. `halt` exits, exactly as in the notes. Every exercise that
asks for a second Terminal session is a second `docker exec` in a second window. A step
that says "run as Administrator" or `sudo` becomes `docker exec -u root`.

**2. "Restart your instance" means restarting IRIS, not the container.**

```
docker exec training-health iris stop IRIS quietly
docker exec training-health iris start IRIS quietly
```

The container stays up while IRIS is down, which is exactly what the notes assume. Do
**not** use `docker compose down` / `up` for a restart: that recreates the container, and
`iris.cpf` is reset when it happens - every namespace, database and mapping you created
by hand would be gone. `docker compose restart` is safe but slower and unnecessary.

Paths, once, for all modules:

| The notes say | Here |
|---|---|
| `C:\InterSystems\training\` | `/usr/irissys` |
| `C:\InterSystems\training\bin\` | `/usr/irissys/bin` |
| the CPF file | `/usr/irissys/iris.cpf` |
| `messages.log` | `/usr/irissys/mgr/messages.log` |
| `C:\Management\` | `/Management` |
| `C:\Databases\` | `/databases` |
| `C:\Backups\` | `/backups` |
| `C:\Journals\jrn\`, `C:\Journals\altjrn\` | `/journals/jrn`, `/journals/altjrn` |
| the encryption key directory | `/InterSystems/training/encryptionkey` |
| `localhost:52773/csp/sys/UtilHome.csp` (Management Portal) | `http://localhost:61773/csp/sys/UtilHome.csp` |
| `localhost:1972` (DBeaver, VS Code, JDBC) | `localhost:61972` |

Always type the full portal path. The bare `http://localhost:61773` returns **HTTP 404**:
the image ships no web server, the portal is served by a separate Web Gateway container,
and the gateway only maps `/csp/...`.

The port is the one your stack publishes:

| Stack | Portal | Superserver |
|---|---|---|
| 1 - `01-health-single` | 61773 | 61972 |
| 2 - `02-code-data-ecp` | 62773 (code), 62774 (data) | 62872 (code), 62873 (data) |
| 3 - `03-mirror-failover` | 63773 (member A), 63774 (member B) | 63972 (A), 63973 (B) |

Stack 2's superserver ports are 628xx rather than 629xx because WinNAT on the training host
had reserved 62943-63042; a reserved port cannot be published at all.

## Where to start

- **Installation (p1-4) cannot be done here** and does not need to be: the container *is*
  the installed instance. Read it, skip it. The one part worth doing is the last step -
  opening a Terminal session and running `^%SS`, `^OPER`, `halt` - with rule 1 above.
- **Architecture, Licensing, Configuring the System (p5-10)** work as printed, with the
  paths above.
- **Configuration for the Application (p11-13)** creates the Phonebook databases,
  namespaces and globals. `install-phonebook.sh` / `.ps1` does exactly this. If you want to
  do p11-13 by hand, **do not run that script** - run only `prepare-instance.sh`. If you
  ran it, p11-13 is already done and you continue at p14.
- **Applications (p14) onwards** is where a prepared instance is meant to be picked up.

## Module by module

### Installation (p1)

- Nothing to install; no installer, no `KitName`, no destination folder, no IIS, no
  InterSystems Launcher, no Windows Client installation, no `setx PATH`. The `iris` command
  is already on the PATH inside the container.
- The licence key is mounted read-only at `/irisdev/keys/<year>/iris.key`; it was applied at
  startup, so there is no "Click License and browse to `iris.key`" step.
- The Web Server port is not 80 or 52773: the licensed image ships no web server, so the
  portal is served by a separate Web Gateway container on the host port in the table above.
- Verify the licence instead: `docker compose logs health | grep -i "LMF Info"`.

### Architecture (p5)

- No difference beyond rule 1. `do ^%CD` and `?` list the namespaces as printed.

### Licensing (p7)

- The multi-machine licence-server exercise needs several instances; only stack 2 and
  stack 3 have two. `do $SYSTEM.License.ShowServer()` works everywhere.
- A licence server address is a Compose **service name** (`data`, `mirror-a`), never an IP
  address or `localhost`.

### Configuring the System (p9)

- `cd /InterSystems/training` becomes `docker exec -it training-health bash` and
  `cd /usr/irissys`.
- The journal directories are `/journals/jrn` and `/journals/altjrn`, created by
  `prepare-instance.sh`.
- "Restart your instance" is rule 2. The step that restarts with a deliberately wrong
  username/password and chooses "use previous startup settings" works as printed.

### Configuration for the Application (p11)

- `<database-dir>` is `/databases`, so `/databases/customer`, `/databases/company` and so
  on. The directory exists already and is writable by IRIS.
- Note whether you are doing this module by hand or having `install-phonebook` do it - see
  *Where to start* above.

### Applications (p14)

- The student files are in `/Management` inside the container, so the `%Installer` class to
  import is `/Management/PhonebookInstaller.xml`.
- The application URLs are on the portal port and there are no Chrome bookmarks:
  `http://localhost:61773/csp/company/Company.csp` and
  `http://localhost:61773/csp/phonebook/Phonebook.AllStart.cls`.
- Anywhere the notes ask for "the IP of your Ubuntu server", use `localhost` - the port is
  published on your own machine.

### Journaling (p17)

- Journal directories as above. Everything else is portal work and is unchanged.

### Backup (p19)

- Backups go to `/backups`, including the "Backup of All on List" configuration.
- Copying a backup file out to look at it: `docker cp training-health:/backups/<file> .`

### Managing Databases (p22)

- Database directories are under `/databases`; expanding or adding one is portal work and
  unchanged.

### Managing Processes (p24)

- `irissession TRAINING -U %SYS "^BACKUP"` becomes
  `docker exec -it training-health iris session IRIS -U %SYS "^BACKUP"`.
- Two Terminal sessions are two `docker exec` windows; terminating one from the other with
  `^JOBEXAM` or from the portal works exactly as printed.

### Review Logs (p26)

- `messages.log` is `/usr/irissys/mgr/messages.log`, readable from the host with
  `docker exec training-health tail -n 100 /usr/irissys/mgr/messages.log`.
- "What does that error code mean for your system" - the container is Linux, so read the
  Ubuntu answer.
- Restarts are rule 2.

### Auditing (p28)

- No difference beyond rule 1. Login and logout entries come from the `docker exec` session.

### System Monitoring (p30)

- `^SystemPerformance` and Diagnostic Report write into `/usr/irissys/mgr` by default.
  "Double-click the HTML file" means copying it out to your own machine first:
  `docker cp training-health:/usr/irissys/mgr/<file>.html .`
- **MailSlurper is replaced by MailHog**, which is in the stack's compose file behind a
  profile, so start it once:

  ```
  docker compose --profile mail up -d
  ```

  Mail Server / SMTP Server is `mail`, port `1025`. The inbox is
  `http://localhost:61026`, not `localhost:8080`.
- **Do not run `MailSlurperConfig.ps1`** - there is nothing to configure; MailHog accepts
  any sender and needs no setup.

### Troubleshooting Basics (p33)

- The utilities are in `/usr/irissys/bin`; run them with
  `docker exec -it -u root training-health bash`, then `cd /usr/irissys/bin`.
- The switch exercises (`^SWSET`, switch 10) and the two-session test are unchanged apart
  from rule 1.

### Automation and Utilities (p35)

- MailHog as in System Monitoring, and again no `MailSlurperConfig.ps1`.
- `^%ZSTART` / `^%ZSTOP`: connect VS Code with the InterSystems ObjectScript extension to
  `http://localhost:61773`, `SuperUser` / `SYS`. There is no Studio in the container.
- `^%ZSTOP` writes `ss.txt` to `/Management`, which exists and is writable.
- "Restart your instance" to trigger them is rule 2 - a container restart would work too,
  but rule 2 is faster and safer.

### Enterprise Cache Protocol (p38)

This module is written for two machines and two participants. Here both machines are yours:
use **stack 2** (`02-code-data-ecp`), which exists for this exercise.

| The notes say | Here |
|---|---|
| the ECP data server (steps 2-5) | `training-ecp-data`, portal 62774 |
| the ECP application server (steps 6-12) | `training-ecp-code`, portal 62773 |
| the data server's IP address | the service name `data`, port `1972` |
| the application server's IP address | the service name `code`, port `1972` |

**Prepare both instances first**, from `common/course/`:

```
./prepare-instance.sh training-ecp-code training-ecp-data
./install-phonebook.sh training-ecp-data
./install-phonebook.sh training-ecp-code
```

The module operates on the Phonebook databases, and stack 2 ships only its own `TRAINCODE` /
`TRAINDATA` and the `TRAINING` / `DATA` namespaces. Step 8 points a remote database at
`/databases/company/` **on the data server**, and steps 10-11 need the `PHONEBOOK` namespace
and the Company page **on the application server** - so the Phonebook has to be installed on
both, or done by hand on both through the earlier modules.

Step by step, where it differs:

- **1** (agree the roles with your partner) is decided by the table above.
- **2** (enable the ECP service, data server only) is a real step: `%Service_ECP` is disabled
  by default on 2026.1. The printed route works (System Administration → Configuration → ECP
  Settings → *This System as an ECP Data Server* → *Enable ECP service*), and so does System
  Administration → Security → Services → `%Service_ECP`. Skip it and step 7 never leaves
  *Not Connected*.
- **3-5** (raise the maximum number of application servers, then restart) can be skipped:
  there is one application server here. If you change it anyway, the restart is rule 2.
- **4** has no `ipconfig` and no instructor-provided address. The data server's address is
  the Compose service name **`data`**, port **`1972`** - not an IP, not `localhost`, and not
  the published host port 62873, which only reaches the instance from your own machine.
- **6** on the application server: keep the printed *Server name* (`DataServer`) and put
  `data` in the *IP Address* field. Whatever name you choose here is the one you must select
  as the *Server* in step 8. Stack 2's own [EXERCISE.md](../../02-code-data-ecp/EXERCISE.md)
  uses `DATA` for the same field - either is fine, but do not mix them.
- **7** (change the connection status to Normal) is a real step, and the state before it looks
  alarming: the new row reads *Not Connected* with *IP Address* `0.0.0.0`. That is correct -
  ECP connects on first use, so nothing has resolved the host name yet. *Change Status* →
  *Normal* brings the connection up and the address becomes the data container's address on
  the stack network. Measured on this pair: afterwards the application server's ECP server
  list says `Normal`, and the data server's client list shows the connection. If it will not
  reach *Normal*, that is when step 2 was missed.
- **8** (`REMOTECOMPANY`): the directory is the Ubuntu path from the notes,
  **`/databases/company/`**, because that is where `install-phonebook.sh` put the COMPANY
  database on the data server. The path is read on the data server, not on this one. The
  printed route exists here, as System Administration → **Configuration** → **Remote
  Databases** → *Create Remote Database* - a separate page from *Local Databases*, whose
  *Create New Database* button only makes local ones. Set *Server* first: the *Directory*
  dropdown is filled by asking that server, so it stays empty until step 7 is done.
- **10-12** (map `Phonebook.Company*` to `REMOTECOMPANY` in `PHONEBOOK`) work as printed.
- **11**: there are no Chrome bookmarks. The Company page of the application server is
  `http://localhost:62773/csp/company/Company.csp`. "Your partner's companies" are the rows
  now served from the data server; both instances were seeded with the same five, so the
  convincing test is to create a new company here and find it on the data server at
  `http://localhost:62774/csp/company/Company.csp`.
- **Expect a delay** before a global written on the application server appears on the data
  server: ECP flushes modified blocks asynchronously. Read it again a few seconds later
  before concluding the setup is broken.
- **13** (look at the ECP processes on both sides): System Operation → Processes in each
  portal, or `^%SS` in a `docker exec` session on each container.
- **14** (find the journal entries on the data server): stack 2's journal directory is the
  default **`/usr/irissys/mgr/journal/`**, *not* `/journals/jrn`. That path only becomes the
  journal directory in the instance where you did the Configuring the System module, which
  is stack 1.
- **15** (delete the mapping) works as printed, and leaving it in place breaks nothing.

### Mirroring (p40)

Use **stack 3** (`03-mirror-failover`), whose two members are already journalled, licensed and
running an ISCAgent.

| The notes say | Here |
|---|---|
| Machine A (starts primary) | `training-mirror-a`, portal 63773, superserver 63972 |
| Machine B (starts backup) | `training-mirror-b`, portal 63774, superserver 63973 |
| Machine C (optional async DR) | does not exist - skip every Machine C step |
| Machine A's IP address | the service name `mirror-a` |
| Machine B's IP address | the service name `mirror-b` |
| Machine A's instance name | **`IRIS`**, not `TRAINING` |
| the arbiter address | `arbiter`, only if you started the arbiter profile |

**Prepare both members first**, from `common/course/`:

```
./prepare-instance.sh training-mirror-a training-mirror-b
./install-phonebook.sh training-mirror-a
./install-phonebook.sh training-mirror-b
```

Steps 5 and 10-18 all operate on the COMPANY, CUSTOMER and PERSONAL databases and the
`PHONEBOOK` namespace, and stack 3 ships only its own `MIRRORDATA` / `MIRRORNS`. Both members
need the Phonebook - which is also what the notes assume when they say Machine B "already has
those databases from earlier exercises".

- The two warnings before step 1 do not apply. Nothing autofills a hostname, because every
  address you type is a Compose service name, and 1972 / 2188 need no firewall work: they are
  reachable on the stack's own network.
- **2** (enable `%Service_Mirror` on all machines) is a real step on both members - the
  service is disabled by default on 2026.1.
- **3** (verify the ISCAgent) is already done: `iris-main` starts the agent on 2188 in both
  containers. There is no Windows service and no `/etc/init.d/ISCAgent`.
- **4** (create the mirror on Machine A). Keep the printed mirror and member names. The
  fields that differ:

  | Field | Value |
  |---|---|
  | Require SSL/TLS | **No** - the exercise is about mirroring, not certificates |
  | Use Arbiter | **No** by default; `arbiter` / 2188 if you started the profile |
  | Use Virtual IP | **No** - see below |
  | SuperServer Address | `mirror-a` |
  | Mirror Agent Port | 2188 |

  Stack 3's own [EXERCISE.md](../../03-mirror-failover/EXERCISE.md) uses `TRAINMIRROR` /
  `MEMBERA` / `MEMBERB` for the same three names. Use one set or the other, not both.
- **There is no virtual IP and there cannot be one**: a VIP needs the members to share a
  subnet on which an interface can be moved between hosts, which a Docker bridge network does
  not provide. Connect to whichever member you mean, through its own portal.
- **7** (join as failover on Machine B): *Agent Address on other system* is `mirror-a`, port
  2188, and *Instance Name* is **`IRIS`**. On the second page, the member's *SuperServer
  Address*, *Mirror Private Address* and *Agent Address* are all `mirror-b`.
- **8** and every other Machine C step: no third instance here. Skip them.
- **10-12 is the route to take** - both members are 2026.1, so IRIS downloads the mirrored
  databases from the primary by itself. Run `do ##class(MIS.Simulation).CopyToHolder()` in the
  **`PHONEBOOK`** namespace on member B (`docker exec -it training-mirror-b iris session IRIS
  -U PHONEBOOK`), then recreate COMPANY, CUSTOMER and PERSONAL in their original
  `/databases/...` directories with *Mirrored Database: Yes*, then repoint the `PHONEBOOK`
  namespace. Both members use the same paths, so nothing has to be renamed.
- **13-15** (the backup/restore alternative) needs no `robocopy` and no `scp`: move the `.cbk`
  through the host with two commands, `docker cp training-mirror-a:/backups/<file> .` then
  `docker cp <file> training-mirror-b:/backups/`. Because the paths on the two members are
  identical, the restore is the "directory paths match" case - accept each default.
- **16-17**: the pages on member B are
  `http://localhost:63774/csp/company/Company.csp` and
  `http://localhost:63774/csp/phonebook/Phonebook.AllStart.cls`.
- **19-20** (stop IRIS on A, watch B take over) is where this stack deliberately differs.
  Stopping IRIS is rule 2, `docker exec training-mirror-a iris stop IRIS quietly`, and the
  container stays up. **Without an arbiter, member B will not promote itself** - it cannot
  tell a stopped partner from a broken network, so takeover is an operator decision: force it
  from the Mirror Monitor on B, from `^MIRROR`, or with
  `do ##class(SYS.Mirror).BecomePrimary()`. To see the automatic behaviour the notes describe,
  start the arbiter first (`docker compose --profile arbiter up -d`) and give its address in
  step 4. `iris start IRIS quietly` on A brings it back as the backup.
- **22** (remove the mirror configuration) works as printed, with rule 2 for each restart. If
  you only want a clean slate, `docker compose down -v` and `up -d` is faster and also
  discards the Phonebook, so re-run the two scripts above afterwards.
- **23-27** (the optional `^MIRROR` QoS and forced-failover exercise) work as printed with
  rule 1. Step 25 is the same manual takeover as step 19, which is what stack 3 was built to
  demonstrate.

### Encryption (p45)

- The key directory `/InterSystems/training/encryptionkey` exists already -
  `prepare-instance.sh` creates it with the exact path the notes use.
- The encrypted database goes in `/databases/encrypted/`.
- "Restart the system, keep the Unattended startup" is rule 2.

### Security Installation (p47)

- No Command Prompt and no Administrator: everything here is portal work, plus rule 1 for
  the Terminal steps.

### Authentication (p48)

- **`%Service_Console` does not exist here.** The container is Linux, so everywhere the
  notes say `%Service_Console` (Windows) or `%Service_Terminal` (Ubuntu), it is always
  **`%Service_Terminal`**. This applies to the Authorization modules too.
- `irissession TRAINING` is `docker exec -it training-health iris session IRIS`.
- The eight OS accounts the Operating System authentication step needs already exist:
  `sumi`, `chris`, `olaf`, `anita`, `bo`, `vic`, `robin`, `fred`. The password is the
  username, except `bo`, whose password is `bobo`.
- Two-factor SMS: MailHog, as in System Monitoring - SMTP server `mail`, inbox
  `http://localhost:61026`.

### Authorization: Basics, Services and Resources, Applications, Putting It All Together (p50-59)

- `%Service_Console` → `%Service_Terminal` throughout, as above.
- "Log into Terminal as Anita/Olaf/Bo" means
  `docker exec -it training-health iris session IRIS` and entering that username - the
  accounts are IRIS users created by the Phonebook installer, not the OS accounts.
- "Using VS Code, open `Phonebook.int`": the VS Code connection from the Automation module.

### Security Administration (p60)

- No difference beyond rule 1.

### SQL Security (p61)

- DBeaver runs on your own machine and connects to `localhost:61972` (or your stack's
  superserver port), namespace `PHONEBOOK`, not to `localhost:1972`.

## If something is missing

Re-run the preparation script. It reports `OK` or `FAILED` for each directory, each OS
account and the student files, and repairs whatever is missing:

```
./prepare-instance.sh training-health          # or  .\prepare-instance.ps1 training-health
```

It is idempotent and leaves a populated `/Management` alone, so nothing done during the
exercises is lost. The one thing a container recreate always loses is the eight OS accounts,
because they live in the container's writable layer - this restores them and changes nothing
else.
