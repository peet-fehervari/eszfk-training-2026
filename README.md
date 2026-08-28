# IRIS 2026.1 training stacks

Three independent Docker Compose environments for training on InterSystems IRIS
2026.1, built from [spec.txt](spec.txt):

| Directory | What it is |
|---|---|
| [01-health-single/](01-health-single/) | one IRIS for Health instance with a portal |
| [02-code-data-ecp/](02-code-data-ecp/) | code/functions on one instance, data on another, over ECP |
| [03-mirror-failover/](03-mirror-failover/) | two failover members, no arbiter - manual takeover |

Each stack is a separate Compose project with its own network and its own named
volumes, so they can run at the same time or one at a time without interfering.

**Stacks 2 and 3 come up prepared but not wired.** Enabling ECP and building the
mirror is the training content, not something the stack does at startup. Both have an
`EXERCISE.md` with the portal steps and a `setup/` directory with the same steps as
scripts, for resetting or for checking an answer. Do not "helpfully" move the wiring
into the compose files.

## Prerequisites

- Docker with the Compose plugin.
- Access to `containers.intersystems.com` - `docker login containers.intersystems.com`.
  These are licensed images, not the community edition.
- A licence key. The key store is a directory of four-digit year subdirectories:

  ```
  <key store>/2026/iris.key
  ```

  The default location is `../../../keys` relative to a stack directory - a sibling of
  this repository's parent. Override it in `.env`:

  ```bash
  cp .env.example .env      # then edit IRIS_KEY_DIR
  ```

  `common/start.sh` picks the newest year directory that contains a `*.key` and passes
  it to `iris-main` as `--key <file>`. Nothing is copied and nothing is written: the
  store is mounted read-only.

The Advanced Server key in use here (`Multi_Server=enabled`, 128 cores) licenses ECP
and mirroring, and was verified to license the IRIS for Health image as well.

## Ports

Chosen above the host ephemeral range (32768-60999) so they cannot collide with an
outbound connection, and clear of the ports other projects in this workspace use.

| Stack | Instance | Superserver | Portal | ISCAgent |
|---|---|---|---|---|
| 1 | health | 61972 | 61773 | |
| 2 | code | 62972 | 62773 | |
| 2 | data | 62973 | 62774 | |
| 3 | member A | 63972 | 63773 | 63188 |
| 3 | member B | 63973 | 63774 | 63189 |

Inside the containers everything stays on the native ports (1972, 2188, 80), so
container-to-container configuration always uses service names and native ports -
`mirror-a:2188`, `data:1972`. The published host ports are for you, not for the
instances.

## Running a stack

From the stack's directory:

```bash
docker compose up -d
docker compose ps                                    # wait for healthy
docker compose logs <service> | grep -i "LMF Info"   # confirm it is licensed
```

Then open that stack's portal (see its README) and log in as `SuperUser` / `SYS`.

Stop, keeping the instances' data:

```bash
docker compose down
```

Reset to a clean first-start state:

```bash
docker compose down -v
```

## How the stacks are built

- **`common/start.sh`** is the entrypoint for every IRIS service. It only finds the
  licence key and then `exec`s `/iris-main`. It is set as
  `entrypoint: ["/tini","--","/irisdev/common/start.sh"]` so tini stays PID 1 and
  keeps reaping processes, exactly as the unmodified image does.
- **CPF merge** does the first-start configuration. Each stack points
  `ISC_CPF_MERGE_FILE` at a file whose `[Actions]` section creates its databases and
  namespaces and makes `SuperUser` logon-ready. This runs before IRIS starts and is
  idempotent, so a restart is harmless.
- **A Web Gateway container per instance.** The licensed image has `WebServer=0` and
  no web server of its own, so a gateway is the only way to reach the Management
  Portal. There is one per instance rather than one shared gateway with app paths,
  because the portal emits absolute `/csp/sys/...` links and path-based multiplexing
  breaks its navigation.
- **A named volume over `/usr/irissys/mgr`** per instance for durable data. The
  documented `ISC_DATA_DIRECTORY` durable-%SYS mechanism does not work with a fresh
  named volume here: Docker creates the volume's mount point owned by root while IRIS
  runs as uid 51773, and initialisation fails with
  `ERROR #5001: Cannot create target`. Mounting over a directory that already exists
  in the image avoids this, because Docker seeds the volume with that directory's
  contents and ownership.
- **The image's own healthcheck**, `/irisHealth.sh`, on a 10s interval instead of the
  image's 60s. Gateways wait on `service_healthy`.

## Troubleshooting

**The instance started but nothing is licensed.** An unlicensed start looks almost
normal - it just fails later on ECP or mirroring. Check the log:

```bash
docker compose logs <service> | grep -i "LMF"
```

`LMF Info: Licensed for N cores` is what you want. If instead `start.sh` printed
`WARNING - no *.key found`, the key store is not where `IRIS_KEY_DIR` says it is, or
it has no year subdirectory.

**The portal is empty, or the browser shows nothing on the portal port.** The gateway
is up but cannot reach its instance. Check that the instance is healthy
(`docker compose ps`) and that the `Ip_Address` in the stack's `CSP.ini` is the
Compose **service name**, not `localhost`.

**Every portal URL returns HTTP 200.** That proves nothing: an unauthenticated request
returns the login page with status 200, including for page names that do not exist.
Log in before concluding a page works.

**Piping ObjectScript into `iris session` fails with `<SYNTAX>`.** Each line of piped
input is evaluated as if typed at the `%SYS>` prompt, so multi-line blocks - `FOR`,
`IF`, `$$$` macros - do not survive. One complete command per line, ending with
`halt`. `common/setup-lib.sh` wraps this.

## Repository layout

```
common/          entrypoint, base CPF merge, shared Apache config, setup helpers
01-health-single/
02-code-data-ecp/    cpf/  setup/  webgateway/  EXERCISE.md
03-mirror-failover/  cpf/  setup/  webgateway/  EXERCISE.md
spec.txt         the original requirement
```
