# "Managing InterSystems Servers" course add-on

Turns an already-running instance from any of the three stacks into the environment the
course exercises expect: the directories, the OS accounts and the student files. No stack of
its own, no image build, no configuration to edit - one script, and optionally a second one
that installs the Phonebook application instead of the participant.

Where the exercise text says something that is different in a container - a path, a port,
a command - it is listed module by module in [COURSE-NOTES.md](COURSE-NOTES.md).

## 1. Put two files in place

Both are licensed material, so neither is in this repository.

| What | Where it goes |
|---|---|
| The IRIS licence key | `keys/2026/iris.key` at the top of this repository (`2026` = the licence year) |
| The course student files | `common/course/material/` - the **contents** of `StudentFilesforManagementDirectory`, not the folder around them |

Create `material/` yourself; it is gitignored, so it does not exist in a fresh clone. The
files, as the archive ships them:

```
common/course/material/
├── ClassFilesExplained.txt
├── MIS.Simulation.xml
├── MailSlurperConfig.ps1
├── PhonebookClasses.xml
├── PhonebookInstaller.xml
├── swcvt.xml
├── zstart.xml
├── DelegatedAuthentication/
│   ├── README.txt
│   ├── ZAuth.xml
│   └── Zen.xml
└── PhonebookFiles/
    ├── Company.csp
    └── cube_logo_blue.gif
```

`Thumbs.db` and any other Windows artefact can be skipped.

To keep either of them somewhere else: `COURSE_MATERIAL_DIR=/somewhere/else
./prepare-instance.sh training-health` for the files, and for the key copy `.env.example`
to `.env` **in the stack directory you start** and set `IRIS_KEY_DIR`. A `.env` in the
repository root is not read - Compose only reads the one next to the compose file it runs.

## 2. Install

```bash
cd 01-health-single
docker compose up -d
docker compose ps                      # wait until both containers are healthy

cd ../common/course
./prepare-instance.sh training-health
```

On Windows, the same script in PowerShell: `.\prepare-instance.ps1 training-health`.

That is the whole installation. It creates, inside the container:

- `/Management`, `/databases`, `/backups`, `/journals/jrn`, `/journals/altjrn` and
  `/InterSystems/training/encryptionkey`, owned by the IRIS user, so every exercise that
  types a path can type the one in the printed notes;
- the eight OS accounts the authentication module logs in as - `sumi`, `chris`, `olaf`,
  `anita`, `bo`, `vic`, `robin`, `fred` (password = username, except `bo`, whose password
  is `bobo`);
- a copy of the student files in `/Management`.

It prints `OK` or `FAILED` for each of those and ends with `Prerequisites in place. The
exercises can be started.` **Re-run it whenever you want to check or repair the same
things**: it is idempotent, it reports the current state, and it leaves a populated
`/Management` alone. There is no separate check script to remember.

Every path is a variable with the course's own default (`COURSE_DIRS`, `MANAGEMENT_DIR`,
`DB_DIR`, `BACKUP_DIR`, `COURSE_MATERIAL_DIR`, `COURSE_OS_USERS`), so the material can live
outside the repository and the directories can be moved without editing a script. Nothing
has to be set for the default course layout.

## 3. Optional - skip ahead past the application setup

```bash
./install-phonebook.sh training-health          # .\install-phonebook.ps1 on Windows
```

**This script does exercise work**, and it is the only one that does. It runs the course's
own `%Installer`, which creates the databases, the `PHONEBOOK` namespace, the global
mappings and the `/csp/phonebook` and `/csp/company` applications - exactly what the
"Configuration for the Application" and "Applications" modules have the participant create
by hand. It then imports `MIS.Simulation`, the helper class the backup and monitoring
exercises call.

So there is one choice to make:

| | Run it | Do not run it |
|---|---|---|
| The exercises start at | the **Applications** module | the **Configuration for the Application** module |
| The Phonebook application is | already installed | built by the participant, as the course intends |

Everything from Journaling onwards operates on the Phonebook databases, so a participant
who does not get through those two modules cannot do the rest either. That is what this
script is for - as a shortcut for a demo instance, or as a rescue for somebody who got
stuck. It is not idempotent: if the databases already exist the installer stops with
`ERROR #20: the file already exists`, and the way back is `docker compose down -v`.

## 4. Start the exercises

Portal at `http://localhost:61773/csp/sys/UtilHome.csp`, `SuperUser` / `SYS`.

The Installation module cannot be done in a container - IRIS is already installed - so read
it and skip it. Then read [COURSE-NOTES.md](COURSE-NOTES.md): two rules there ("open a
Terminal session" and "restart your instance") cover most of the differences on their own,
and the rest is listed module by module.

One thing worth checking first, because an unlicensed instance starts almost silently and
only fails much later:

```bash
docker compose logs health | grep -i "LMF Info"      # expect: Licensed for N cores
```

## Which container, which port

| Stack | Container for the scripts | Second instance | Portal |
|---|---|---|---|
| `01-health-single` | `training-health` | - | 61773 |
| `02-code-data-ecp` | `training-ecp-code` | `training-ecp-data` | 62773 (code), 62774 (data) |
| `03-mirror-failover` | `training-mirror-a` | `training-mirror-b` | 63773 (A), 63774 (B) |

Always type the full portal path, `http://localhost:<port>/csp/sys/UtilHome.csp`. The bare
host and port returns HTTP 404: the image has no web server of its own, and the Web Gateway
container in front of it only maps `/csp/...`.

Pick one stack and stay with it. The second instance in stacks 2 and 3 is the partner machine
that the ECP and mirroring modules need, and **both instances have to be prepared** -
`prepare-instance.sh` takes any number of containers at once, `install-phonebook.sh` one at a
time:

```bash
./prepare-instance.sh training-mirror-a training-mirror-b
./install-phonebook.sh training-mirror-a
./install-phonebook.sh training-mirror-b
```

Both modules work on the Phonebook databases on *both* machines, so if you are doing the
Configuration and Applications modules by hand instead, do them on both.
[COURSE-NOTES.md](COURSE-NOTES.md) lists the exact settings for each of the two modules.

## Two things to know about restarting

- **`iris stop`/`iris start` is free.** Every exercise that restarts the instance works,
  and the container stays up while IRIS is down.
- **A container recreate loses the OS accounts.** They live in the container's writable
  layer, not in a volume, so after any `docker compose down`/`up` re-run
  `prepare-instance.sh` - it is idempotent, and it leaves `/Management` alone once
  populated. Everything else survives: the instance configuration and all the course
  directories are volumes.

Full reset, discarding everything including the work done in the exercises:

```bash
docker compose down -v && docker compose up -d
../common/course/prepare-instance.sh training-health
../common/course/install-phonebook.sh training-health    # only if it was used before
```

Use `-v`. A `down` without it keeps the volumes but the Phonebook installer will not
create a database over a leftover `IRIS.DAT`.

## Optional: the mail server

Four exercises send mail (`^MONMGR`, Task Manager, two-factor authentication). MailHog
does the job MailSlurper does on a Windows desktop and is in every stack's compose file
behind a profile, because it is the one image not from `containers.intersystems.com` and a
failed pull must not take IRIS with it:

```bash
docker compose --profile mail up -d
```

In IRIS use SMTP host `mail`, port `1025`; the inbox is at `http://localhost:61026`. Do
not run `MailSlurperConfig.ps1` - MailHog needs no configuration.

## No CPF change is needed

The only IRIS setting the course depends on is `SuperUser` not being forced to change its
password, and every stack's CPF merge already sets it. Everything else the exercises
configure is what the exercises are for.
