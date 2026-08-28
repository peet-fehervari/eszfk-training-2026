# Stack 2 - code instance + data instance (ECP)

Two licensed IRIS 2026.1 instances with split roles. Classes, routines and
utilities live on the **code** instance; the data they operate on lives on the
**data** instance and is reached over ECP.

The stack comes up prepared but **not connected** - wiring ECP is the exercise.
See [EXERCISE.md](EXERCISE.md).

| Service | Container | Host port | Purpose |
|---|---|---|---|
| `code` | `training-ecp-code` | 62972 | Superserver of the code/application instance |
| `data` | `training-ecp-data` | 62973 | Superserver of the data instance |
| `code-portal` | `training-ecp-code-portal` | 62773 | Management Portal of `code` |
| `data-portal` | `training-ecp-data-portal` | 62774 | Management Portal of `data` |

## Run

```bash
docker compose up -d
docker compose ps
docker compose down -v          # -v discards both instances' data
```

Portals: <http://localhost:62773> (code) and <http://localhost:62774> (data),
`SuperUser` / `SYS`.

## Prepared state

| | code instance | data instance |
|---|---|---|
| Database | `TRAINCODE` at `/usr/irissys/mgr/traincode/` | `TRAINDATA` at `/usr/irissys/mgr/traindata/` |
| Namespace | `TRAINING` - globals and routines both local | `DATA` over `TRAINDATA` |
| `%Service_ECP` | - | disabled, on purpose |

Databases and namespaces are created declaratively by the CPF merge files in
[cpf/](cpf/), applied on every container start and idempotent.

## Scripts

Run from the `setup/` directory. They exist to reset the environment or to
demonstrate the finished state - the exercise is to do the same in the portal.

| Script | Does |
|---|---|
| `01-data-server.sh` | Enables `%Service_ECP` on the data instance |
| `02-code-server.sh` | Adds the ECP server, creates the remote database, remaps `TRAINING` globals |
| `verify.sh` | Proves the split, and refuses if the stack is not wired yet |

`verify.sh` also works after doing the exercise by hand, so it can be used to check
a participant's own work. Container names can be overridden with the
`CODE_CONTAINER` and `DATA_CONTAINER` environment variables.

## Notes

- **Use `data:1972`, not `localhost:62973`, for the ECP connection.** The host port
  is for tools on your machine; container-to-container traffic uses the service
  name and the in-container port.
- **ECP writes are not instant.** Modified blocks sit in the ECP client cache before
  reaching the data server, so a global written on `code` may take a few seconds to
  appear on `data`. This surprises people into thinking the setup is broken.
- The `depends_on` on `code` is ordering convenience only. The code instance starts
  fine without the data instance; the ECP connection is created later, by hand.
