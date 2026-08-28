# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

Three Docker Compose training stacks for **licensed InterSystems IRIS 2026.1**, built from
[spec.txt](spec.txt) (the requirements source of truth, written in the user's language — everything
this repository *produces* is English-only, per the workspace `CLAUDE.md` one level up, whose rules
this repository inherits):

| Directory | Topology |
|---|---|
| `01-health-single/` | one `irishealth:2026.1` instance + portal |
| `02-code-data-ecp/` | code/functions instance + data instance, joined over ECP |
| `03-mirror-failover/` | two failover members, no arbiter, manual takeover |

There is no build and no test suite. Verification is running a stack and observing it; the commands
are in [README.md](README.md) and each stack's README.

## The stacks are intentionally not self-configuring

Stacks 2 and 3 come up with every prerequisite satisfied and the interesting part **deliberately
undone** — ECP is not enabled, no mirror exists. That wiring is the training exercise. Each stack has
an `EXERCISE.md` with the portal steps and a `setup/` directory scripting the same steps for resets.

Do not move that configuration into the compose files, the CPF merges, or an `-a` startup hook. If a
stack looks unfinished, check its `EXERCISE.md` before "fixing" it.

## Structure

`common/` holds what every stack shares, mounted read-only into the containers or sourced by host
scripts: `start.sh` (entrypoint), `merge-base.cpf`, `webgateway/CSP.conf`, `setup-lib.sh`. Compose
files reach it with relative paths (`../common/...`). Per-stack differences live in the stack's own
`cpf/` and `webgateway/` directories.

## Verified facts about the 2026.1 images

These were checked against the real images. Several contradict what the sibling
`java-iris-transactions` project does — that project targets an older release, so do not copy its
entrypoint or healthcheck without re-checking.

- The real entrypoint is `/tini -- /iris-main`. A custom entrypoint must keep tini as PID 1:
  `entrypoint: ["/tini","--","/irisdev/common/start.sh"]`.
- The container runs as uid **51773** (`irisowner`). Mounted scripts need mode 755.
- **`--check-caps` does nothing** on 2026.1 — the flag's own help says it is retained for backwards
  compatibility only. Do not pass it and do not reintroduce the "IRIS refuses to start without it"
  rationale.
- `iris-main` offers `-a` (after start), `-b`, `-c`, `-t`, `-l` hooks. No hand-rolled background
  poller is needed if post-start automation is ever wanted — but see the section above.
- **ISCAgent starts by default** on 2188. The mirror prerequisite is already met.
- `WebServer=0` and no httpd in the image, so the Web Gateway container is genuinely mandatory for a
  Management Portal.
- `%Service_ECP` and `%Service_Mirror` are both **disabled** by default.
- `SuperUser` has `ChangePassword=1`, but `CSPSystem` is already `0` — the CPF merge only needs the
  `SuperUser` line.
- The images **do** carry a healthcheck script, `/irisHealth.sh`, used by the image's own 60s
  HEALTHCHECK. Reuse it on a tighter interval instead of probing `/dev/tcp`.
- Mirroring lives in **`SYS.Mirror`**, not `%SYSTEM.Mirror`. Useful methods: `CreateNewMirrorSet`,
  `JoinMirrorAsFailoverMember`, `AddDatabase`, `AddDatabaseNonPrimary`, `BecomePrimary`,
  `IsMirrorStarted`, `GetFailoverMemberStatus(&ThisMember,&OtherMember)` (both are `$list`s:
  1=name, 3=role, 4=status).
- **Durable %SYS via `ISC_DATA_DIRECTORY` does not work with a fresh named volume.** Docker creates
  the mount point root-owned, IRIS runs as 51773, and initialisation fails with
  `ERROR #5001: Cannot create target`. These stacks mount a named volume over `/usr/irissys/mgr`
  instead, which Docker seeds with the image directory's contents and ownership.
- **ECP writes are buffered.** A global written on the code instance can take several seconds to be
  visible in the database on the data instance. Poll; do not conclude the mapping is broken.
- **Every portal URL returns HTTP 200 unauthenticated**, including page names that do not exist — the
  login page is served with status 200. HTTP 200 is not evidence that a page or a class exists; check
  `%Dictionary.CompiledClass` instead.
- **Piping multi-line ObjectScript into `iris session` fails.** Each line is evaluated as if typed at
  the `%SYS>` prompt, so `FOR`/`IF` blocks and `$$$` macros break with `<SYNTAX>`. One complete
  command per line, ending with `halt`. `common/setup-lib.sh` wraps this as `os <container>`.

## Licence key

The licensed images require a key; it is never committed and no absolute host path to it appears in
any file. `common/start.sh` walks `${IRIS_KEY_ROOT:-/irisdev/keys}/<year>/`, newest four-digit year
first, takes the first `*.key` and passes it as `--key <file>` (a **file** path, not a directory).

Compose mounts the store read-only: `${IRIS_KEY_DIR:-../../../keys}:/irisdev/keys:ro`. Note the
depth — `../../../keys` from a *stack* directory, not `../../keys`. Layout: `<store>/2026/iris.key`.

The key in use is `Product=Advanced Server`, `Multi_Server=enabled`, 128 cores, expiring 2026-11-30.
It licenses ECP and mirroring, and it was verified to license the IRIS for Health image too.

Confirm a licence actually loaded — an unlicensed start is nearly silent and only fails later:

```bash
docker compose logs <service> | grep -i "LMF Info"    # expect: Licensed for N cores
```

## Web Gateway

One gateway container **per IRIS instance**, not one shared gateway with app paths: the portal emits
absolute `/csp/sys/...` links, so path-based multiplexing breaks its navigation.

Configured by two bind-mounted files via `ISC_CSP_CONF_FILE` and `ISC_CSP_INI_FILE`:
`common/webgateway/CSP.conf` (shared Apache config) and a per-instance `CSP.ini` whose `Ip_Address` is
the Compose **service name** with `TCP_Port=1972`. `CSP.ini` contains a password — it is a protected
file under the workspace rules, so ask before modifying one.

## First-start configuration

All of it happens through CPF merge, pointed at by `ISC_CPF_MERGE_FILE`. It runs before IRIS starts
and is idempotent, so restarts are harmless. The `[Actions]` verbs used here:

```ini
[Actions]
ModifyUser:Name=SuperUser,ChangePassword=0
CreateDatabase:Name=EXAMPLE,Directory=/usr/irissys/mgr/example
CreateNamespace:Name=EXAMPLE,Globals=EXAMPLE,Routines=EXAMPLE
```

Prefer a CPF action over post-start scripting wherever one exists.

## Ports

All three stacks must be startable at once. Host ports are allocated in **61000–63999** — above the
host ephemeral range (32768–60999) and clear of the ports other workspace projects use. Container-side
ports stay native (1972, 2188, 80), so container-to-container configuration always uses service names
and native ports (`data:1972`, `mirror-a:2188`), never `localhost` or a published port. The full map
is in [README.md](README.md); keep it current when adding an instance.

## Working with a running stack

```bash
cd <stack> && docker compose up -d
docker compose ps                          # wait for healthy
docker compose logs -f <service>
docker compose down                        # -v to discard the data volumes and reset

docker exec -it <container> iris session IRIS -U %SYS
```

## Client naming

The directories above this repository, and the repository directory name itself, contain a client
identifier that exists only on this machine. Never write those names, or any path containing them,
into a file here — not in code, comments, docs, config, log output or commit messages. Refer to
sibling projects by their own project name (e.g. `java-iris-transactions`) and to paths inside them
with the parent elided (`.../java-iris-transactions/iris-init/start.sh`). Grep for client identifiers
before finishing a task that added file content.
