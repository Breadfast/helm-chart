# RudderStack gateway / processor-router split — source investigation findings

**Author:** investigation for Breadfast Segment→self-hosted RudderStack migration
**Date:** 2026-06-17
**Status:** Phase 1 deliverable — awaiting review before Phase 2

---

## Investigated ref

| Item | Value | How determined |
|------|-------|----------------|
| **rudder-server image** | `rudderlabs/rudder-server:1.74.1` | [`values-non-prod.yaml:13-14`](/Users/macbook/play/ruddlestack/values-non-prod.yaml) (`backend.image.version: 1.74.1`) |
| **rudder-transformer image** | `rudderstack/rudder-transformer:1.74.1` | [`values-non-prod.yaml:131-134`](/Users/macbook/play/ruddlestack/values-non-prod.yaml) |
| **Investigated git ref** | tag **`v1.74.1`** (commit `15455a2c210747df7e5cd3ca0f23a8563913a7a7`, _"chore: release 1.74.1 (#6927)"_) | `git tag` confirmed `v1.74.1` exists locally |

> The local working checkout sits on `master` (`v1.75.0-11-g516ba5b05`), which does **not** match the deployed tag. The entire investigation below was conducted against a read-only worktree checked out at `v1.74.1` (`git worktree add --detach /tmp/rudder-1.74.1 v1.74.1`). This source repo was not modified. All `file:line` references resolve against `v1.74.1`. The `rudder-go-kit` references resolve against `v0.75.0`, the version pinned in `go.mod` at this ref.

The current non-prod chart deploys a **single** rudder-server pod in default (EMBEDDED) mode — `kind: StatefulSet`, `replicas: {{ .Values.global.backendReplicaCount }}` with `backendReplicaCount: 1` ([`templates/statefulset.yaml:4,14`](/Users/macbook/play/ruddlestack/templates/statefulset.yaml), [`values.yaml:27`](/Users/macbook/play/ruddlestack/values.yaml)). No `APP_TYPE` is set anywhere in the chart, so it runs as `EMBEDDED`. The split topology is **not** what is deployed today.

---

## Verdict

**The hypothesised split is SUPPORTED — but the mechanism is `APP_TYPE`, not the `enableProcessor`/`enableRouter` flags, and there are important caveats.**

> "Multiple stateless **gateway-only** pods (processor and router disabled) for ingestion HA, plus a **single processor/router** pod that handles processing, routing, warehouse syncs, and JobsDB migrations — all against one shared external JobsDB."

This maps cleanly onto rudder-server's three **app types**, selected by the `APP_TYPE` environment variable ([`app/app.go:25-27`](/Users/macbook/play/rudder-server), [`runner/runner.go:70`](/Users/macbook/play/rudder-server)):

- **`APP_TYPE=GATEWAY`** → gateway-only pod. No processor, no router, no warehouse code is constructed. Safe to run N replicas behind the ingress for HA.
- **`APP_TYPE=PROCESSOR`** → processor + router + batch-router + archiver + schema-forwarder, **plus** the warehouse service (embedded). This is the single "brain" pod.
- **`APP_TYPE=EMBEDDED`** (default) → everything in one process (today's topology).

The code **explicitly anticipates running separate gateway and processor instances** against one shared DB — see the comment at [`jobsdb/jobsdb.go:1007-1011`](/Users/macbook/play/rudder-server) ("When running separate gw and processor instances we cannot control the order of execution…"). This is a recognised pattern at the code level.

### Critical corrections to the hypothesis' assumptions

1. **There is no `enableGateway` / `RSERVER_ENABLE_GATEWAY` flag.** The gateway is enabled/disabled solely by `APP_TYPE` (GATEWAY/EMBEDDED include it; PROCESSOR does not).
2. **`enableProcessor` and `enableRouter` are NOT the split mechanism.** Under the default `DEDICATED` deployment type they only feed a static mode resolver that flips the whole pipeline between `NormalMode` and `DegradedMode`. They are effectively **all-or-nothing and coupled**: you need *both* `true` to run the pipeline; if *either* is `false`, **neither** processor nor router runs (see Q1/Q2). You cannot use them to get a "processor-only" or "router-only" pod. For the processor/router pod, leave both at their default `true`.
3. **Warehouse confinement is automatic with `APP_TYPE`**, not something the mode flags control — `GATEWAY` pods never start the warehouse service regardless of any flag (see Q4).

---

## Recommended env vars per role

`RSERVER_`-prefixed names are derived by `ConfigKeyToEnv` ([`rudder-go-kit@v0.75.0/config/config_env.go:19-47`](/Users/macbook/go/pkg/mod)): camelCase→snake_case, `.`→`_`, uppercased, prefixed with `RSERVER_`. **Keys that are already all-uppercase (e.g. `APP_TYPE`, `DEST_TRANSFORM_URL`, `CONFIG_BACKEND_URL`) are used verbatim with NO prefix** ([`config_env.go:10-24`](/Users/macbook/go/pkg/mod)).

| Variable | Gateway-only pod | Processor/router pod | Notes |
|----------|------------------|----------------------|-------|
| `APP_TYPE` | `GATEWAY` | `PROCESSOR` | **The split switch.** No `RSERVER_` prefix (already uppercase). |
| `RSERVER_ENABLE_PROCESSOR` | *(ignored)* | `true` (default) | Both must be true on processor pod → `NormalMode`. Ignored for GATEWAY app. |
| `RSERVER_ENABLE_ROUTER` | *(ignored)* | `true` (default) | See above. |
| `RSERVER_WAREHOUSE_MODE` | *(n/a — warehouse never starts)* | `embedded` (default) | Set `off` to disable warehouse entirely on the processor pod. `master`/`slave` would split warehouse out (out of scope). |
| `DEST_TRANSFORM_URL` | **required** (reachable) | **required** (reachable) | Both poll the transformer `/features` on startup. No prefix. |
| `CONFIG_BACKEND_URL` | **required** | **required** | Backend/control-plane config. No prefix. Already set in non-prod via `extraEnvVars`. |
| `DB.host` / `DB.port` / `DB.name` / `DB.user` / `DB.password` / `DB.sslMode` → `RSERVER_DB_HOST` etc. | **required (read+write)** | **required (read+write)** | Gateway writes `gw_*` tables; processor writes `rt/batch_rt/esch/arc` and reads `gw_*`. (Exact Cloud SQL wiring is Phase 2.) |
| `RSERVER_GATEWAY_WEB_PORT` | `8080` (default) | n/a | Gateway HTTP listener + `/health`. |
| `RSERVER_PROCESSOR_WEB_PORT` | n/a | `8086` (default) | Processor health-only listener. |
| `DEPLOYMENT_TYPE` | leave unset (`DEDICATED`) | leave unset (`DEDICATED`) | **Do not set `MULTITENANT`** — that switches mode control to ETCD (see Q1). |

> The "ignored" cells are deliberate: for a GATEWAY app the cluster controller forces `NormalMode` and ignores all mode logic ([`app/cluster/dynamic.go:83-85,108-111,127-129,201-204`](/Users/macbook/play/rudder-server)), so `enableProcessor`/`enableRouter` have no effect there.

---

## Evidence per question

### Q1 — Mode toggling: can gateway / processor / router be independently enabled/disabled?

**Two orthogonal mechanisms exist:**

**(a) `APP_TYPE` selects the app handler** — this is the real component switch:
- `app/app.go:25-27` — constants `GATEWAY = "GATEWAY"`, `PROCESSOR = "PROCESSOR"`, `EMBEDDED = "EMBEDDED"`.
- `runner/runner.go:70` — `appType: strings.ToUpper(config.GetStringVar(app.EMBEDDED, "APP_TYPE"))` — default `EMBEDDED`.
- `app/apphandlers/setup.go:34-46` — `GetAppHandler` switches on `appType` and returns `gatewayApp` / `processorApp` / `embeddedApp`. Unknown values are a fatal error (`unsupported app type`).

**(b) `enableProcessor` / `enableRouter` feed the static mode resolver** (only relevant for PROCESSOR/EMBEDDED apps, under `DEDICATED` deployment):
- `app/apphandlers/setup.go:89-90` — `enableProcessor := config.GetBoolVar(true, "enableProcessor")`, `enableRouter := config.GetBoolVar(true, "enableRouter")`. Both default **true**.
- `app/apphandlers/setup.go:95-101` — the static provider returns `NormalMode` **iff `enableProcessor && enableRouter`**, otherwise `DegradedMode`. → coupled, all-or-nothing.
- `app/apphandlers/setup.go:107-117` — provider selection depends on `DEPLOYMENT_TYPE`: `DEDICATED` → static provider (uses the flags); `MULTITENANT` → ETCD dynamic provider (flags irrelevant; mode pushed via ETCD). Default deployment type is `DEDICATED` ([`utils/types/deployment/deployment.go:25,29-39`](/Users/macbook/play/rudder-server)).

**Env var names (verified against `ConfigKeyToEnv`):** `enableProcessor` → `RSERVER_ENABLE_PROCESSOR`; `enableRouter` → `RSERVER_ENABLE_ROUTER`; `Warehouse.mode` → `RSERVER_WAREHOUSE_MODE`; `APP_TYPE` → `APP_TYPE` (verbatim). Your candidate names `RSERVER_ENABLE_PROCESSOR`/`RSERVER_ENABLE_ROUTER` are **correct**; there is **no** gateway-enable flag.

### Q2 — Bootstrap gating: where are components conditionally initialized?

- **App handler dispatch:** `runner/runner.go:148` — `r.appHandler, err = apphandlers.GetAppHandler(r.application, r.appType, …)`; started at `runner/runner.go:219-225` (`if r.canStartServer()` → `StartRudderCore`).
- **Gateway app — only the gateway is built:** `app/apphandlers/gatewayAppHandler.go:88-97` builds the `gw` JobsDB (writer); `:155-164` sets up the gateway; `:171-173` starts `gw.StartWebHandler`. No processor/router objects are constructed at all. The cluster controller is created with `GatewayComponent: true` (`:125`).
- **Processor app — processor + router built and gated by mode:** `app/apphandlers/processorAppHandler.go:299-318` builds the processor; `:324-351` builds router + batch-router (`routerManager.New`); `:353-372` wires them into `cluster.Dynamic{GatewayComponent:false, Processor:p, Router:rt, …}`; `:382` `dm.Run(ctx)` starts them **only when the resolved mode is `NormalMode`**.
- **Mode → start/stop gate:** `app/cluster/dynamic.go:200-242` `handleModeChange` — `DegradedMode→NormalMode` calls `start()` (`:126-165`, which starts RouterDB, BatchRouterDB, PartitionMigrator, Processor, Archiver, SchemaForwarder, Router); `NormalMode→DegradedMode` calls `stop()` (`:167-198`). For a `GatewayComponent` the controller forces `NormalMode` and **all of `start`/`stop`/`handleModeChange` early-return** (`:83-85,127-129,168-170,201-204`) — the gateway just keeps running and ignores mode events (`:108-111`).
- **Embedded app — gateway always on, pipeline gated by mode:** `app/apphandlers/embeddedAppHandler.go:392-411` always starts the gateway web handler; `:356-374,417` wires processor/router into `cluster.Dynamic` (no `GatewayComponent`) gated the same way.

### Q3 — JobsDB migrations: where do they run on startup, and are they pod-safe?

Two layers, **both serialized by PostgreSQL advisory locks**, so multiple pods against one shared DB are safe (they queue, not race):

1. **Node-level schema migrations** run in **every** app's `Setup()`:
   - `app/apphandlers/setup.go:48-54` — `rudderCoreDBValidator()` → `validators.ValidateEnv()`; `rudderCoreNodeSetup()` → `validators.InitializeNodeMigrations()`.
   - Called by gateway (`gatewayAppHandler.go:40-45`), processor (`processorAppHandler.go:80-85`), and embedded (`embeddedAppHandler.go:69-74`).
   - `services/validators/envValidator.go:140-156` — runs `golang-migrate` against the `node_migrations` table.
   - The migrator uses `github.com/golang-migrate/migrate/v4` with the postgres driver (`services/sql-migrator/migrator.go:12-17,62,151,181`), which acquires a **pg advisory lock** during `Migrate()` — concurrent pods serialize.

2. **Per-dataset JobsDB table setup** runs on each writer handle's `Start()`:
   - `jobsdb/jobsdb.go:1001-1002` — `if writer { jd.setupDatabaseTables(templateData) }`. **Only writer handles create/migrate tables.**
   - `jobsdb/setup.go:26-38` — uses the same advisory-locked `golang-migrate` migrator (per-prefix `*_schema_migrations` table).
   - `jobsdb/jobsdb.go:1005-1012` + `jobsdb/setup.go:40-51` — `runAlwaysChangesets` runs for **both** readers and writers, explicitly to handle the case where gw and processor run as separate instances and ordering can't be guaranteed.

**Per-pod safety / `killDanglingDBConnections`:** `ValidateEnv()` also kills dangling connections (`services/validators/envValidator.go:52-57`) via `application_name LIKE ('%' || CURRENT_SETTING('APPLICATION_NAME'))`. The `application_name` is `<first-2-chars-of-component>-<hostname>` and the kill is **scoped to the pod's own hostname** by design (`utils/misc/dbutils.go:40-53`, see the comment at `:46-48`). Because each k8s pod has a unique hostname (pod name), **one gateway pod will not kill another's connections** — confirmed safe for N gateway replicas.

→ **Multiple gateway-only pods + one processor pod against one shared DB is safe.** Migrations serialize on advisory locks; connection-killing is per-pod.

### Q4 — Warehouse sync ownership

- `runner/runner.go:341-343` — `canStartWarehouse()` returns **`r.appType != app.GATEWAY && r.warehouseMode != config.OffMode`**.
- `runner/runner.go:246-253` — warehouse service started only if `canStartWarehouse()`.
- `runner/runner.go:73` — `warehouseMode` defaults to `embedded` (`Warehouse.mode` / `RSERVER_WAREHOUSE_MODE`).

→ **GATEWAY pods never run the warehouse service**, regardless of any flag. The single PROCESSOR pod runs warehouse syncs embedded (default `embedded` mode). Confining warehouse syncs to the one processor/router pod is therefore **automatic** under this split — directly addressing the duplicate-sync / cost concern. (Set `RSERVER_WAREHOUSE_MODE=off` on the processor pod only if you want no warehouse at all; `master`/`slave` would be a separate warehouse-pod split, out of scope.)

### Q5 — Per-mode dependencies

| Dependency | Gateway-only (`APP_TYPE=GATEWAY`) | Processor/router (`APP_TYPE=PROCESSOR`) |
|------------|-----------------------------------|------------------------------------------|
| **JobsDB write** | **Yes** — writes `gw_*` tables. `gatewayAppHandler.go:88-101` (`jobsdb.NewForWrite("gw")` + `Start()`). | **Yes** — `rt`, `batch_rt`, `esch`, `arc` are ReadWrite writers; `gw` is read-only. `processorAppHandler.go:185-239`. |
| **Transformer URL** (`DEST_TRANSFORM_URL`) | **Yes, and blocking** — polls `/features`; web handler won't bind until it succeeds (`gatewayAppHandler.go:139-143`, `gateway/handle_lifecycle.go:543-553`, `services/transformer/features_impl.go:97-117`). | **Yes** — needed for user transformations & dest transforms (`processorAppHandler.go:146-150`). |
| **Backend/control-plane config** (`CONFIG_BACKEND_URL`) | **Yes, and blocking** — web handler waits on `backendConfigInitialisedChan` (`gateway/handle_lifecycle.go:537-541`). | **Yes** (`processorAppHandler.go:116`). |
| **Outbound destination access** | **No** — gateway only ingests and writes to `gw_*`. | **Yes** — the router/batch-router deliver to destinations; warehouse uploads to object store. |

### Q6 — Health / readiness endpoints per mode

- **Gateway:** `GET /health` and `GET /` on `Gateway.webPort` (default **8080**, `RSERVER_GATEWAY_WEB_PORT`) — `gateway/handle_lifecycle.go:87,624-625`, handler `app.LivenessHandler` (`app/app.go:138-147`). Returns **503** if `jobsDB.Ping()` fails (`app/app.go:149-159`, `:140-144`). **The port does not bind until backend config *and* transformer features are loaded** (`gateway/handle_lifecycle.go:535-553`), so a TCP/HTTP readiness probe on `:8080` naturally reflects "ready to ingest". ⇒ Probe gateway pods on **`:8080/health`**.
- **Processor/router:** dedicated health-only listener `GET /health` and `GET /` on `Processor.webPort` (default **8086**, `RSERVER_PROCESSOR_WEB_PORT`) — `processorAppHandler.go:399-416,73`. Same `LivenessHandler` (pings the `gw` read DB). ⇒ Probe processor pod on **`:8086/health`**. (No event-ingest port is opened on a PROCESSOR pod.)
- **Embedded (today):** gateway handler on `:8080` (`embeddedAppHandler.go:409-411`) — matches the current chart's probe target (`templates/statefulset.yaml:90-99` probes `targetPort` 8080).

Note: liveness == "can ping JobsDB". With an external Cloud SQL DB, **all** probes turn red if the DB is unreachable — relevant for Phase 2 probe tuning (avoid mass restarts during a brief DB blip; prefer generous `failureThreshold`/`timeoutSeconds`).

### Q7 — In-repo precedent for the split topology

- **No Helm charts, k8s manifests, docker-compose, or docs in the repo demonstrate the split.** `APP_TYPE` appears in source only — `app/app.go:165` and `runner/runner.go:70` — and in **no** `.md`, `.yaml`, `.json`, `Dockerfile`, or test file at `v1.74.1`.
- **However, the split is explicitly supported at the code level**, not incidental: the JobsDB migration logic has a dedicated code path and comment for "running separate gw and processor instances" where execution order can't be controlled (`jobsdb/jobsdb.go:1005-1012`). The three distinct app-type handlers (`gatewayApp`, `processorApp`, `embeddedApp`) and the `canStartWarehouse`/`GatewayComponent` gating are all first-class.

→ Precedent in this repo is **code-level (strong), manifest/doc-level (absent)**. We will be authoring the first manifests for this topology ourselves — there is no in-repo example to copy.

---

## Risks & unknowns for a prod HA design

1. **Gateway readiness hard-depends on the transformer.** A gateway pod will not bind `:8080` until it successfully fetches `/features` from `DEST_TRANSFORM_URL` (`gateway/handle_lifecycle.go:543-553`, `services/transformer/features_impl.go:97-117`). If the transformer is down, **no gateway pod becomes ready and ingestion is fully down**, even though the gateways are otherwise stateless. ⇒ The transformer must itself be HA, and gateway startup ordering depends on it.

2. **`enableProcessor`/`enableRouter` are coupled, not independent.** In `DEDICATED` mode you cannot run a router-only or processor-only pod via these flags — either both run (`NormalMode`) or neither (`DegradedMode`) (`app/apphandlers/setup.go:95-101`). The hypothesis' "single processor/router pod" is fine (both `true`), but the wording "processor and router disabled" for the gateway pods is achieved by `APP_TYPE=GATEWAY`, **not** by setting these flags false.

3. **Single processor pod = single point of failure for processing/routing/warehouse.** Ingestion stays HA (gateways buffer to `gw_*` in the shared DB), but if the processor pod is down, nothing drains `gw_*` → events accumulate in the DB until it returns. Acceptable for a deliberate active/standby design, but the processor should be a `StatefulSet`/single-replica with fast reschedule, and we must **not** run two processor pods in `DEDICATED` static mode (both would process the same jobs → double delivery). True processor HA needs `MULTITENANT`+ETCD leader election, which is a much larger change (out of scope; flag for later).

4. **Startup ordering of `gw_*` tables.** Only writer handles create tables (`jobsdb/jobsdb.go:1001-1002`); the processor opens `gw` **read-only** (`processorAppHandler.go:185-194`). So `gw_*` tables are created by gateway pods. The processor's `runAlwaysChangesets` (reader path) mitigates schema drift (`jobsdb/jobsdb.go:1005-1012`), but on a brand-new DB the processor should tolerate `gw_*` not yet existing until a gateway has started. Verify first-boot ordering during rollout (consider starting at least one gateway before the processor, or rely on the always-changesets path).

5. **Migrations serialize across all pods on rollout.** Every pod runs node migrations on `Setup()` and writers run table migrations on `Start()`, all advisory-locked (`services/sql-migrator/migrator.go`, `jobsdb/setup.go`). On a version bump with schema changes, N+1 pods will queue on the lock — generally fine, but startup can be slower; size readiness/`initialDelaySeconds` accordingly.

6. **Drain-on-scaledown for gateways.** Gateway pods write to `gw_*` and have a graceful shutdown path (`gw.Shutdown()`, `gatewayAppHandler.go:165-169`; `GracefulShutdownTimeout` default 15s, `runner/runner.go:75,280-296`). Confirm the in-flight HTTP requests are flushed within `terminationGracePeriodSeconds` so we don't drop accepted events on scale-down/rolling update. (Behaviour confirmed present; tuning is a Phase 2 concern.)

7. **`DEPLOYMENT_TYPE` must stay `DEDICATED`.** Setting `MULTITENANT` would route mode control through ETCD (`app/apphandlers/setup.go:107-110`) and require an ETCD cluster + workspace/connection-token plumbing — do not set it for this design.

---

## Suggested topology for Phase 2 (for discussion, not yet decided)

- **Gateway:** `Deployment`, N replicas (HA), `APP_TYPE=GATEWAY`, behind the existing nginx ingress (`events.breadfast.tech`), probes on `:8080/health`.
- **Processor/router:** `StatefulSet`, **1 replica**, `APP_TYPE=PROCESSOR`, `RSERVER_ENABLE_PROCESSOR=true`, `RSERVER_ENABLE_ROUTER=true`, `RSERVER_WAREHOUSE_MODE=embedded`, probes on `:8086/health`. Owns warehouse syncs and the bulk of JobsDB migrations.
- **Shared external Cloud SQL** as the single JobsDB for both roles (Phase 2 wiring).
- **Transformer:** must be HA since gateway readiness depends on it.

**Open questions to resolve with you in Phase 2:** (a) confirm single-processor active/standby is acceptable vs. investing in MULTITENANT+ETCD; (b) Cloud SQL `sslmode` and connection-pool sizing (`DB.gateway.Pool.*` vs `DB.processor.Pool.*` defaults differ — 20 vs 80 max conns, `gatewayAppHandler.go:75-79`, `processorAppHandler.go:158-162`); (c) where `gw_*` first-boot table creation should be guaranteed in the rollout order.

---

_End of Phase 1 findings. Stopping here for review before any Phase 2 chart work._
