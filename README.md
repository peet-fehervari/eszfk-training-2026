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

For the course exercises, two more steps - the details are in
[common/course/README.md](common/course/README.md):

6. Copy the course student files into `common/course/material/` (licensed material, handed
   out separately - the file list is in
   [common/course/PREREQUISITES.md](common/course/PREREQUISITES.md)).

7. Prepare the running instance and check it:

   ```bash
   cd ../common/course
   ./prepare-instance.sh training-health      # directories, OS accounts, student files
   ./install-phonebook.sh training-health     # the Phonebook application
   ./verify.sh training-health 61773          # expect: No failures
   ```

## Ports

| Stack | Instance | Superserver | Portal | ISCAgent |
|---|---|---|---|---|
| 1 | health | 61972 | 61773 | |
| 2 | code | 62972 | 62773 | |
| 2 | data | 62973 | 62774 | |
| 3 | member A | 63972 | 63773 | 63188 |
| 3 | member B | 63973 | 63774 | 63189 |

The course overlay adds the mail server on 61025 (SMTP) and 61026 (inbox), and stack 3's
arbiter on 63190. Every port is a `.env` override, because on a Windows host WinNAT
reserves blocks of high ports and a reserved port cannot be published at all.

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
