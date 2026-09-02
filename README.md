# IRIS 2026.1 training stacks

Three independent Docker Compose environments for training on licensed InterSystems
IRIS 2026.1, plus an add-on for the "Managing InterSystems Servers" course.

## What is in each directory

| Directory | One line |
|---|---|
| [01-health-single/](01-health-single/) | One IRIS for Health instance with a Management Portal - nothing to wire. |
| [02-code-data-ecp/](02-code-data-ecp/) | Two instances, code and data, ready for ECP; enabling ECP is the exercise ([EXERCISE.md](02-code-data-ecp/EXERCISE.md)). |
| [03-mirror-failover/](03-mirror-failover/) | Two failover members with no arbiter, so takeover is manual; building the mirror is the exercise ([EXERCISE.md](03-mirror-failover/EXERCISE.md)). |
| [common/](common/) | What every stack shares: entrypoint, base CPF merge, Apache config, script helpers - and [common/course/](common/course/), the course add-on. |
| `keys/` | Where the licence key goes. Gitignored, so it is not in the repository. |

Each stack is its own Compose project, so they can run at the same time or one at a time.

## Install

1. Log in to the image registry - these are licensed images:

   ```bash
   docker login containers.intersystems.com
   ```

2. Copy your licence key into this repository as:

   ```
   keys/2026/iris.key
   ```

3. Start a stack:

   ```bash
   cd 01-health-single
   docker compose up -d
   ```

4. Check IRIS is up and licensed:

   ```bash
   docker compose ps                                    # wait for healthy
   docker compose logs health | grep -i "LMF Info"      # expect: Licensed for N cores
   ```

5. Open the portal and log in as `SuperUser` / `SYS`:
   <http://localhost:61773/csp/sys/UtilHome.csp>

For the "Managing InterSystems Servers" course, two more steps - the file list and what the
script does are in [common/course/README.md](common/course/README.md):

6. Copy the course student files into `common/course/material/` (licensed material, handed
   out separately).

7. Prepare the running instance:

   ```bash
   cd ../common/course
   ./prepare-instance.sh training-health      # directories, OS accounts, student files
   ```

   On Windows, in PowerShell:

   ```powershell
   cd ..\common\course
   .\prepare-instance.ps1 training-health
   ```

   Re-run it at any time to check or repair the same things; it is idempotent, so there is
   no separate check script. `./install-phonebook.sh training-health` - in PowerShell
   `.\install-phonebook.ps1 training-health` - is optional and is the one script that does
   exercise work: it installs the Phonebook application instead of the participant, letting
   the exercises start at the "Applications" module.

   [common/course/COURSE-NOTES.md](common/course/COURSE-NOTES.md) then lists, module by
   module, every place where this environment differs from the printed exercise notes.

## Ports

| Stack | Instance | Superserver | Portal | ISCAgent |
|---|---|---|---|---|
| 1 | health | 61972 | 61773 | |
| 2 | code | 62872 | 62773 | |
| 2 | data | 62873 | 62774 | |
| 3 | member A | 63972 | 63773 | 63188 |
| 3 | member B | 63973 | 63774 | 63189 |

The pattern is `6<stack>972` for the superserver and `6<stack>773` for the portal. Stack 2's
two superserver ports are the exception - 628xx instead of 629xx - because WinNAT on the
training host had reserved the block 62943-63042, and a reserved port cannot be published at
all. The portals are unaffected.

Two optional containers, started only with their profile, add the mail server on 61025
(SMTP) and 61026 (inbox) and stack 3's arbiter on 63190:

```bash
docker compose --profile mail up -d        # any stack: MailHog for the mail exercises
docker compose --profile arbiter up -d     # stack 3 only
```

Every port is a `.env` override, because on a Windows host WinNAT reserves blocks of high
ports, dynamically and differently after each reboot, and a reserved port cannot be
published at all - Compose then fails with `/forwards/expose returned unexpected status:
500` and nothing is listening, which looks like a Docker fault rather than a port
conflict. List the reserved blocks with
`netsh int ipv4 show excludedportrange tcp` and move the port in the stack's `.env`.

Inside the containers everything stays on the native ports (1972, 2188, 80), so
container-to-container configuration uses service names: `data:1972`, `mirror-a:2188`.

## Other Docker commands

```bash
docker compose logs -f <service>                     # follow one service
docker compose down                                  # stop, keep the data
docker compose down -v                               # reset to a clean first start
docker exec -it <container> iris session IRIS -U %SYS # ObjectScript prompt
docker exec -it <container> bash                     # shell as irisowner
docker exec -u root -it <container> bash             # shell as root
docker exec <container> iris stop IRIS quietly       # stops IRIS, not the container
docker exec <container> iris start IRIS quietly
```

The licence key can live outside the repository: copy `.env.example` to `.env` **in the
stack directory you start** and point `IRIS_KEY_DIR` at that directory.
