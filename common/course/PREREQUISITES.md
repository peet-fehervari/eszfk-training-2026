# Prerequisites and what differs from the printed notes

Read this once before the first exercise. Two things have to be put in place by hand, and
a handful of paths in the course text are different in a container.

The examples use stack 1 (`training-health`, portal 61773). Substitute your own container
and port from the table in [README.md](README.md) if you started a different stack.

## 1. What you must place, and exactly where

Both are licensed material, so neither is in this repository.

| What | Where it goes | Result if missing |
|---|---|---|
| Course student files | `common/course/material/` — the **contents** of `StudentFilesforManagementDirectory`, file list below | The stack starts and the portal works, but nothing can be imported: no Phonebook application, no `MIS.Simulation` |
| IRIS licence key | `keys/2026/iris.key` at the top of this repository — `keys/` is gitignored, and `2026` is the licence year | The instance starts **unlicensed**: 5 connections, no ECP, no mirroring. The log says `WARNING - no *.key found` |

Neither directory is in the repository: both are gitignored, so create `material/` and copy
the files themselves into it, not the folder around them:

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

`Thumbs.db` and any other Windows artefact in the archive can be skipped. To keep the files
somewhere else entirely, point `COURSE_MATERIAL_DIR` at that directory instead:
`COURSE_MATERIAL_DIR=/somewhere/else ./prepare-instance.sh training-health`.
`prepare-instance.sh` copies them into `/Management`, which is writable, so the steps that
export there work too; it only copies while `/Management` is still empty, so work done
during the exercises is never overwritten.

To keep the key somewhere else instead, copy the repository's `.env.example` to `.env` **in
the stack directory you start** and point `IRIS_KEY_DIR` at that directory. A `.env` in the
repository root is not read — Compose only reads the one next to the compose file it is
running.

Confirm both landed:

```bash
docker compose logs health | grep -i "LMF Info"      # expect: Licensed for N cores
../common/course/verify.sh --no-restart training-health 61773
```

## 2. Directories the exercises use

`prepare-instance.sh` creates all of these inside the container, owned by the IRIS user
(uid 51773), so every exercise that types a path can type the one in the notes.

| Path in the container | Used by |
|---|---|
| `/Management` | Every import step. Filled with the student files, and writable, so the exercises that export there work too |
| `/databases` | The application databases the Phonebook installer creates |
| `/journals/jrn`, `/journals/altjrn` | The journaling exercises: primary and alternate journal directory |
| `/backups` | `^BACKUP`, and `MIS.Simulation.Backup()` / `.Restore()` |
| `/InterSystems/training/encryptionkey` | The encryption key file exercises |
| `/irisdev/out` | Optional, and only with `course-overlay.yml`: a bind mount to `common/course/out`, so `^SystemPerformance` and Diagnostic Report HTML can be opened in a browser without `docker cp`. **It arrives read-only for IRIS** because it carries your host user's ownership; `chmod 777 common/course/out` fixes it, and no `sudo` is needed because you own the directory. Skipping this only means reports stay inside the container |

Nothing here is hard-coded: each path is a variable with the course default, so
`COURSE_DIRS`, `MANAGEMENT_DIR` and friends can move any of them.

## 3. Where the container differs from the notes

| The notes say | Here it is | Why |
|---|---|---|
| Instance name `TRAINING` | Instance name **`IRIS`** | IRIS is preinstalled in the image as `IRIS`. Anywhere a command takes an instance name — `iris start`, `iris stop`, `iris session`, `^SystemPerformance` output names — use `IRIS` |
| Install directory `/InterSystems/training` | **`/usr/irissys`** | The image's install directory. So `/InterSystems/training/bin` → `/usr/irissys/bin`, `mgr` → `/usr/irissys/mgr` |
| The Installation module: run `setup.exe`, choose an install directory, set the instance name | **Not reproducible.** IRIS is already installed | The archive ships a Windows installer, and the image has IRIS baked in. Read the module; the settings it walks through are visible afterwards in the portal and in `iris.cpf` |
| Portal at `http://localhost:57772/csp/sys/` | `http://localhost:61773/csp/sys/UtilHome.csp` | The image has no built-in web server (`WebServer=0`), so a Web Gateway container serves the portal. Log in as `SuperUser` / `SYS` |
| MailSlurper on the Windows desktop, `MailSlurperConfig.ps1` | MailHog: SMTP server **`mail`**, port **`1025`**, inbox at `http://localhost:61026` | Same job, in a container. Start it with `--profile mail`; it is the one image not from `containers.intersystems.com`. The `.ps1` in `material/` is left in place for reference and is not used |
| "Open a Terminal window" | `docker exec -it training-health iris session IRIS -U %SYS` | |
| "Open a Command Prompt" | `docker exec -it training-health bash` | |
| "Restart your instance" | `docker exec training-health iris stop IRIS quietly` then `... iris start IRIS quietly` | Verified: stopping IRIS does **not** stop the container, so the instance can be restarted as often as the exercises ask |
| Anything needing Administrator rights | `docker exec -u root -it training-health bash` | Covers `IRISHung.sh`, renaming `IRIS.DAT` by hand, editing files owned by root |

## 4. About `sudo`

Two separate questions, and the answer to both is that you do not need root:

- **On your own machine**, only `docker` needs privilege. If your user is in the `docker`
  group, no `sudo` at all. If not, prefix every `docker`/`docker compose` command with
  `sudo` — nothing else needs it, because no host directory has to be chowned. The single
  exception is the optional `chmod 777 common/course/out` above, which you can do as
  yourself.
- **Inside the container** there is no `sudo` and it is not installed. Where an exercise
  needs root, use `docker exec -u root` as in the table above.

## 5. Emergency access mode

Two exercises use it. It works here, with one container-specific trap:

```bash
docker exec training-health iris stop IRIS quietly
docker exec training-health iris start IRIS EmergencyId=emgcy,emgcy
```

While in emergency mode **only** that ID can log in — `SuperUser` cannot, and neither can
`iris stop`, which prompts for it and otherwise aborts with `local authentication failure`
while leaving the instance up and locked. To get back out, feed the credentials in:

```bash
printf 'emgcy\nemgcy\n' | docker exec -i training-health iris stop IRIS quietly
docker exec training-health iris start IRIS quietly
```

`verify.sh` exercises this round trip and checks that ordinary logins work again
afterwards.

## 6. Modules that need a second machine

The ECP module needs a second instance and the mirroring module a second failover member.
Stacks 2 and 3 already have one, and `prepare-instance.sh` takes both container names:

```bash
./prepare-instance.sh training-ecp-code training-ecp-data       # ECP module
./prepare-instance.sh training-mirror-a training-mirror-b       # mirroring module
```

Use the **service names and native ports** for the connection between them — `data:1972`,
`mirror-b:1972`, `arbiter:2188` — never `localhost` and never a published port: those
exist only on your machine, not on the container network.

The mirror can be built as the notes describe, with two exceptions a Docker bridge network
cannot provide: there is no virtual IP (a VIP needs an interface that can move between
hosts), and mirror TLS is left off. The arbiter the notes ask for is in stack 3's
`course-overlay.yml` behind the `arbiter` profile.

Stacks 2 and 3 also have their own `EXERCISE.md` covering ECP and mirroring on their own,
independently of this course.

## 7. Resetting

```bash
docker compose -f docker-compose.yml -f course-overlay.yml down -v
docker compose -f docker-compose.yml -f course-overlay.yml up -d
../common/course/prepare-instance.sh training-health
../common/course/install-phonebook.sh training-health
```

`down -v` discards the databases, journals, backups and `/Management`, including anything
you did during the exercises. `down` without `-v` keeps the data but still resets the
instance configuration, so the Applications module has to be redone — and the installer
will not create a database over a leftover `IRIS.DAT`, which is why the reset above uses
`-v`.
