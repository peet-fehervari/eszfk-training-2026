# Stack 1 - single IRIS for Health instance

One licensed IRIS for Health 2026.1 instance plus the Web Gateway that serves its
Management Portal. Nothing else is configured; the instance is a clean starting
point.

| Service | Container | Host port | Purpose |
|---|---|---|---|
| `health` | `training-health` | 61972 | Superserver (JDBC / ODBC / ECP / xDBC) |
| `portal` | `training-health-portal` | 61773 | Management Portal via Web Gateway |

## Run

```bash
docker compose up -d
docker compose ps                  # both containers, health = healthy
docker compose logs -f health
docker compose down                # -v also discards the instance data volume
```

Management Portal: <http://localhost:61773/csp/sys/UtilHome.csp> - `SuperUser` / `SYS`.

ObjectScript shell / SQL shell:

```bash
docker exec -it training-health iris session IRIS
docker exec -it training-health iris sql IRIS
```

## What to check first

The licence is the thing most likely to be wrong, and an unlicensed instance
starts anyway and only fails later:

```bash
docker compose logs health | grep -E 'iris-init:|LMF Info'
```

Expected: a line naming the key file, then `LMF Info: Licensed for 128 cores`.
If instead `iris-init: WARNING - no *.key found` appears, see the repository README
for the key store layout.

## For the "Managing InterSystems Servers" course

This is the stack to use for it, except for the ECP and mirroring modules (stacks 2 and 3).
Start it as above, then:

```bash
cd ../common/course
./prepare-instance.sh training-health       # the whole installation
./install-phonebook.sh training-health      # optional; installs the Phonebook application
```

See [common/course/README.md](../common/course/README.md). The exercise directories
(`/Management`, `/databases`, `/backups`, `/journals`) are already volumes in this stack's
compose file, so only their ownership and the OS accounts have to be set up - which is what
`prepare-instance.sh` does, and what has to be re-run after a container recreate.

## Notes

- The licence used here is an **IRIS Advanced Server** key. It was verified to
  license the IRIS for Health image as well, so no separate health key is needed.
- The portal is *only* reachable through the gateway container. The licensed image
  has `WebServer=0` and ships no httpd, so port 52773 on the IRIS container serves
  nothing - this is not a misconfiguration.
- Interoperability auto-start is on by default (`EnsembleAutoStart=1`), so any
  production created here will restart with the container.
