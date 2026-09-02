# Stack 2 - code instance + data instance (ECP)

Two licensed IRIS 2026.1 instances with split roles. Classes, routines and
utilities live on the **code** instance; the data they operate on lives on the
**data** instance and is reached over ECP.

The stack comes up prepared but **not connected** - wiring ECP is the exercise.
See [EXERCISE.md](EXERCISE.md).

| Service | Container | Host port | Purpose |
|---|---|---|---|
| `code` | `training-ecp-code` | 62872 | Superserver of the code/application instance |
| `data` | `training-ecp-data` | 62873 | Superserver of the data instance |
| `code-portal` | `training-ecp-code-portal` | 62773 | Management Portal of `code` |
| `data-portal` | `training-ecp-data-portal` | 62774 | Management Portal of `data` |

The superserver ports are 628xx, not the 629xx the other stacks' numbering would suggest:
WinNAT on the training host had reserved 62943-63042, which covers 62972 and 62973, and a
reserved port cannot be published at all. Both are `.env` overrides
(`PORT_CODE_SUPERSERVER`, `PORT_DATA_SUPERSERVER`) if the reservations move again.

## Run

```bash
docker compose up -d
docker compose ps
docker compose down -v          # -v discards both instances' data
```

Management Portal - the full path is required, the bare host and port returns HTTP 404
because the Web Gateway only serves `/csp/...`:

| Instance | URL |
|---|---|
| code | <http://localhost:62773/csp/sys/UtilHome.csp> |
| data | <http://localhost:62774/csp/sys/UtilHome.csp> |

Both log in as `SuperUser` / `SYS`.

## Prepared state

| | code instance | data instance |
|---|---|---|
| Database | `TRAINCODE` at `/usr/irissys/mgr/traincode/` | `TRAINDATA` at `/usr/irissys/mgr/traindata/` |
| Namespace | `TRAINING` - globals and routines both local | `DATA` over `TRAINDATA` |
| `%Service_ECP` | - | disabled, on purpose |

Databases and namespaces are created declaratively by the CPF merge files in
[cpf/](cpf/), applied on every container start and idempotent.

There are no scripts in this directory. Everything the stack prepares is done by the compose
file and the CPF merges; the ECP wiring is done by hand in the portal, following
[EXERCISE.md](EXERCISE.md). To start over, `docker compose down -v` and up again.

## For the "Managing InterSystems Servers" course

This is the stack for the course's **Enterprise Cache Protocol** module, which is written for
two machines - here they are the two instances above. Start the stack as above, then prepare
**both** instances:

```bash
cd ../common/course
./prepare-instance.sh training-ecp-code training-ecp-data
./install-phonebook.sh training-ecp-data
./install-phonebook.sh training-ecp-code
```

On Windows, in PowerShell:

```powershell
cd ..\common\course
.\prepare-instance.ps1 training-ecp-code training-ecp-data
.\install-phonebook.ps1 training-ecp-data
.\install-phonebook.ps1 training-ecp-code
```

`prepare-instance` creates the exercise directories' ownership and the OS accounts, and has to
be re-run after a container recreate; it is idempotent and reports `OK`/`FAILED` per
prerequisite, so it doubles as the check. The Phonebook is needed on both sides because the
module's remote database points at `/databases/company/` on the data server while the Company
page is opened on the application server. The module's step-by-step deviations are in
[common/course/COURSE-NOTES.md](../common/course/COURSE-NOTES.md) under *Enterprise Cache
Protocol*; the installation itself is in
[common/course/README.md](../common/course/README.md).

## Notes

- **Use `data:1972`, not `localhost:62873`, for the ECP connection.** The host port
  is for tools on your machine; container-to-container traffic uses the service
  name and the in-container port.
- **A new data server reads *Not Connected*, and that is not an error.** ECP connects on
  first use, so the row stays *Not Connected* with `0.0.0.0` as the address until either
  *Change Status* → *Normal* or the first access to a remote database on it.
- **ECP writes are not instant.** Modified blocks sit in the ECP client cache before
  reaching the data server, so a global written on `code` may take a few seconds to
  appear on `data`. This surprises people into thinking the setup is broken.
- The `depends_on` on `code` is ordering convenience only. The code instance starts
  fine without the data instance; the ECP connection is created later, by hand.
