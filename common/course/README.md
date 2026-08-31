# "Managing InterSystems Servers" course add-on

Turns any already-running instance in this repository into the environment the course
exercises expect. No stack of its own, no image build.

## Getting started

1. **Copy the student files into `material/`.** They are licensed material and are handed
   out separately, so the directory is not in the repository — create it and copy the
   *contents* of `StudentFilesforManagementDirectory` into it. The file list is in
   [PREREQUISITES.md](PREREQUISITES.md).

2. **Start a stack** (any of them; pick one and stay with it):

   ```bash
   cd ../../01-health-single
   docker compose -f docker-compose.yml -f course-overlay.yml up -d
   ```

   `course-overlay.yml` is optional. Without it everything works, but the course
   directories are lost by a container recreate — see *Persistence* below.

3. **Run these two scripts from this directory**, with the container name of the
   instance you started:

   ```bash
   cd ../common/course
   ./prepare-instance.sh training-health      # directories, OS accounts, student files
   ./install-phonebook.sh training-health     # the "Applications" module, scripted
   ```

4. **Check IRIS is working:**

   ```bash
   ./verify.sh training-health 61773
   ```

   Expect `No failures`. The one warning on a default start is the mail server, which is
   optional. Add `--no-restart` to skip the part that stops and starts IRIS.

5. **Log in to the portal** at `http://localhost:61773/csp/sys/UtilHome.csp` as
   `SuperUser` / `SYS`, and start the exercises. Read
   [PREREQUISITES.md](PREREQUISITES.md) first: it lists every point where the container
   differs from the printed notes (instance name, paths, how to restart the instance).

## Which container and which port

| Stack | Container to pass to the scripts | Portal port |
|---|---|---|
| `01-health-single` | `training-health` | 61773 |
| `02-code-data-ecp` | `training-ecp-code` | 62773 |
| `03-mirror-failover` | `training-mirror-a` | 63773 |

Stacks 2 and 3 have a second instance (`training-ecp-data`, `training-mirror-b`) that the
ECP and mirroring modules can use as the partner machine. `prepare-instance.sh` takes
several container names at once.

## Persistence

`prepare-instance.sh` creates the course directories and the OS accounts *inside a running
container*. That survives `docker compose restart` and `stop`/`start`, and is lost by
`down` or any recreate — the container's writable layer goes with it.

- Adding the stack's `course-overlay.yml` makes the course directories named volumes, so
  their contents survive everything but `down -v`. The OS accounts still do not.
- **After any recreate, re-run `prepare-instance.sh`.** It is idempotent and leaves
  `/Management` alone once populated.
- Note that the *instance configuration* (`iris.cpf`: databases, namespaces, mappings) is
  not in a volume either, so a recreate resets it while the database files remain. To redo
  the Applications module cleanly, start from `docker compose down -v`.

## The three scripts

| Script | What it does |
|---|---|
| `prepare-instance.sh <container>...` | Creates `/Management`, `/databases`, `/backups`, `/journals/{jrn,altjrn}` and `/InterSystems/training/encryptionkey` owned by uid 51773; creates the eight OS accounts the authentication module logs in as; copies the student files into `/Management` |
| `install-phonebook.sh <container>` | Imports `PhonebookInstaller.xml` and runs `RunInstall`, then imports `MIS.Simulation` — the "Applications" module without doing it by hand |
| `verify.sh [--no-restart] <container> [portal port]` | Checks licence, directories, the Phonebook application, `MIS.Simulation`, the web applications, OS accounts, ISCAgent, and the stop/start plus emergency-access-mode round trip |

Every path is a variable with the course's own default (`COURSE_DIRS`, `MANAGEMENT_DIR`,
`DB_DIR`, `BACKUP_DIR`, `COURSE_MATERIAL_DIR`, `COURSE_OS_USERS`), so the material can
live outside the repository and the directories can be moved without editing a script.

## No CPF change is needed

The only IRIS setting the course depends on is `SuperUser` not being forced to change its
password, and every stack's CPF merge already sets it. Everything else the exercises
configure is what the exercises are for.
