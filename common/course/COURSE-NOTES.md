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
| `localhost:52773` (Management Portal, CSP apps) | `http://localhost:61773` |
| `localhost:1972` (DBeaver, VS Code, JDBC) | `localhost:61972` |

The portal port is the one your stack publishes: 61773 for stack 1, 62773/62774 for
stack 2's two instances, 63773/63774 for stack 3's two members. Same for the superserver:
61972, 62972/62973, 63972/63973.

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

- This module needs two instances: use **stack 2** (`02-code-data-ecp`), which is built for
  it, and run `prepare-instance.sh` on both containers.
- There is no `ipconfig` step. The data server's address is the Compose service name
  `data` with port `1972` - not an IP, not `localhost`, not the published host port.
- The remote database directory is the path *on the data instance*: `/databases/company/`
  after the Phonebook install, or `/usr/irissys/mgr/traindata/` for stack 2's own
  `TRAINDATA`.
- Expect a delay before a global written on the application server appears on the data
  server: ECP flushes modified blocks asynchronously. It is not a broken setup.

### Mirroring (p40)

- Use **stack 3** (`03-mirror-failover`), whose two members are already journalled and
  licensed, and run `prepare-instance.sh training-mirror-a training-mirror-b`.
- **The ISCAgent is already running** on port 2188 in both containers - `iris-main` starts
  it. There is no Windows Service and no `/etc/init.d/ISCAgent` to start.
- Instance name on each member is `IRIS`, not `TRAINING`. Addresses are the service names
  `mirror-a` and `mirror-b`, agent port `2188`.
- **Use Arbiter: No** by default - stack 3 deliberately has no arbiter, which is why
  takeover is a manual decision. For the arbiter variant, start it with
  `docker compose --profile arbiter up -d` and use address `arbiter`, port `2188`.
- There is no virtual IP; a Docker bridge network cannot move an interface between hosts.
  Connect to a member directly or through its own portal.
- `robocopy` to the partner becomes two commands on the host:
  `docker cp training-mirror-a:/backups/<file> .` then
  `docker cp <file> training-mirror-b:/backups/`.
- Forcing the backup to become primary from `^MIRROR` works as printed; stopping the
  primary is `docker stop training-mirror-a`, and `docker start` brings it back as backup.

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
