# qjsp Project Implementation Plan

## 0. Purpose

This document describes the implementation strategy and a practical progress checklist for the **qjsp** project (QuickJS hosted by a Pascal/FPC application). It focuses on:

- Operational safety (no hangs, predictable resource usage, controlled process/network/filesystem access).
- Consistent runtime behavior (same JS execution pipeline across REPL/tests/automation).
- Clear boundaries and policies so the project can evolve from a REPL/dev tool into automation and production use.

This plan is written to be used as a tracking artifact (checklist + acceptance criteria + test matrix).

---

## 1. Current Architecture (as implemented)

### 1.1 Host entrypoint

- File: `pascal/src/app/qjsp.pas`
- Responsibilities:
  - Create `JSRuntime` and `JSContext`.
  - Initialize handlers (`js_std_init_handlers(rt)`).
  - Enable blocking (`JS_SetCanBlock(rt, True)`) for timers/async polling.
  - Register built-in modules and shims.
  - Configure debug/dump.
  - Install the module loader (`JS_SetModuleLoaderFunc`).
  - Execute JS and then run pending jobs / event loop.

### 1.2 Module loader

- File: `pascal/src/app/qjsp_module_loader.pas`
- Behavior:
  - `lib:` resolves via config `libraries` mounts.
  - `qjsp:` resolves to `js/libs/` or falls back to `js/runtime/`.
  - Fallback delegates to QAR/filesystem loader (`qar_helpers.js_module_loader_wrapper`).
  - Prevents circular imports using a load stack.

### 1.3 Spawn shim (high-risk surface)

- File: `pascal/src/modules/qjsp_spawn_shim.pas`
- Current behavior:
  - Uses `TProcess` (FPC).
  - Streams stdout/stderr.
  - Has async completion via `waitAsync` resolved inside `SpawnPoll(ctx)`.
  - Windows kill currently relies on `taskkill` + terminate.

---

## 2. Operating Profiles (required)

The project should support two runtime profiles, with the same core mechanisms but different default limits.

### 2.1 Profile: `dev_repl`

- Goal: convenient interactive development.
- Defaults:
  - Larger timeouts.
  - Larger output limits.
  - More verbose logging.
  - Capabilities enabled for developer convenience (still guarded).

### 2.2 Profile: `prod_automation`

- Goal: predictable and safe automation/production usage.
- Defaults:
  - Strict timeouts.
  - Strict output limits.
  - Lower concurrency.
  - Conservative policies for spawn/http/fs/fs_watch.
  - QAR verification default to `strict`.

---

## 3. Policy / Configuration (recommended schema)

Current config: `pascal/config/qjsp_config.json`.

Recommended additions (may be in the same file or a dedicated policy file):

### 3.1 `settings`

- `profile`: `"dev_repl" | "prod_automation"`

### 3.2 `limits`

- `exec_timeout_ms`
- `memory_mb`
- `max_stack_kb`

### 3.3 `spawn`

- `enabled`: boolean
- `timeout_ms_default`, `timeout_ms_max`
- `max_output_kb_default`, `max_output_kb_max`
- `max_concurrent`
- `allowed_cwd_roots`: string[]
- `env_allowlist`: string[]

### 3.4 `http`

- `enabled`
- `allowed_hosts`: string[]
- `timeout_ms`
- `max_body_kb`

### 3.5 `fs_watch`

- `enabled`
- `allowed_roots`: string[]
- `max_watchers`

---

## 4. Implementation Strategy

### 4.1 Consistent JS execution pipeline

Rule: **every** JS execution path must go through the same pipeline.

Recommended conceptual pipeline:

1. `Eval(...)`
2. `DrainPendingJobs(...)` using `JS_ExecutePendingJob`
3. `SpawnPoll(ctx)` (and other async polls)
4. `js_std_loop(ctx)`

This prevents inconsistent behavior across REPL/load/import/tests.

### 4.2 Operational safety primitives

Minimum set:

- Runtime memory limit (already present).
- Stack limit (recommended).
- Interrupt/timeout for JS execution (recommended).
- Spawn sandbox (required if spawn is available to scripts).

### 4.3 Spawn sandbox: Option 1 (in-process) using `TProcess`

Because spawn is needed in production and scripts may supply commands/args, the following guardrails are required:

- Hard timeout.
- Kill process tree.
- Output size limit.
- Concurrency limit.
- CWD jail (allowed roots only).
- Environment scrubbing (allowlist).
- Audit logging.

Windows-specific recommendation:

- Use **Job Objects** (`CreateJobObject` + `AssignProcessToJobObject`) with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`.
- Assign process using PID (`TProcess.ProcessID`) by opening a handle via `OpenProcess(...)`.
- On timeout: close the job handle to kill the entire tree.

---

## 5. Phased Roadmap + Checklist

The checklist items below are intended to be turned into tickets.

Each item includes:

- Scope
- Acceptance criteria (what must be true to mark it done)
- Test notes

### Phase 0 — Stabilize behavior (foundation)

#### P0-1 Unify JS execution pipeline (DONE)

- Scope:
  - Centralize eval/run/test/REPL into one execution pipeline.
- Acceptance:
  - No remaining execution paths that call `JS_Eval` without draining pending jobs and running the loop.
  - Behavior is consistent between REPL and running a file.
- Tests:
  - Async microtask test passes in REPL and file mode.

#### P0-2 Standardize boundary errors + logging (DONE)

- Scope:
  - Define host error codes (module load failure, spawn policy denial, timeout, etc.).
- Acceptance:
  - Spawn/http/fs_watch violations return consistent errors.
  - Logs include enough context to debug without being excessively noisy.

#### P0-3 Baseline tests runnable (DONE)

- Scope:
  - Ensure existing tests in config run reliably.
- Acceptance:
  - `async_test.js` and `java_test.js` pass consistently.

### Phase 1 — Spawn sandbox minimum viable (Windows + TProcess)

#### P1-1 Kill-tree via Job Object (DONE)

- Scope:
  - Replace/augment `taskkill` with Job Object kill-tree where possible.
- Acceptance:
  - Killing a process also kills its children.
  - No zombie processes remain after timeouts.
- Tests:
  - Spawn a process that spawns a child and sleeps; verify both terminate.

- Implementation:
  - `pascal/src/modules/qjsp_spawn_shim.pas`
  - Windows Job Object integration (fallback to `taskkill` when Job Object APIs unavailable).

#### P1-2 Hard timeout for spawn (DONE)

- Scope:
  - Track start time + timeout per spawned process.
  - Enforce timeout in `SpawnPoll(ctx)`.
- Acceptance:
  - A process exceeding timeout is killed and reported as timed out.

- Implementation:
  - `SpawnPoll(ctx)` enforces per-process `timeoutMs`.
  - `waitSync` and `waitAsync` return `{ code, timedOut, truncated }`.

#### P1-3 Output limit (stdout/stderr) (DONE)

- Scope:
  - Implement maximum output bytes per process.
- Acceptance:
  - A process that floods output cannot crash/hang the host.
  - Output is truncated and marked.

- Implementation:
  - Reader threads push stdout/stderr chunks to a queue and enforce per-process output limits.

#### P1-4 Audit log for spawn (DONE)

- Scope:
  - Log spawn requests/results: cmd/args/cwd/duration/exit code/timedOut/truncated.
- Acceptance:
  - Every spawn produces a single structured log entry.

- Implementation:
  - Audit logging in `RemoveProcById(...)`.

- Tests (manual via `.test`):
  - Added:
    - `pascal/tests/spawn_timeout_test.js`
    - `pascal/tests/spawn_output_limit_test.js`
    - `pascal/tests/spawn_kill_tree_test.js`
  - Result:
    - `.test` passes: `async_test.js`, `java_test.js`, and all Phase 1 spawn tests.

### Phase 2 — Policy enforcement + broader sandboxing

#### P2-1 Profile-based defaults (DONE)

- Scope:
  - Load profile from config and apply default limits.
- Acceptance:
  - `dev_repl` and `prod_automation` behave differently without code changes.

#### P2-2 CWD jail (DONE)

- Scope:
  - Validate `cwd` against `allowed_cwd_roots`.
- Acceptance:
  - Disallowed cwd is rejected with a clear error.

#### P2-3 Environment scrubbing (DONE)

- Scope:
  - Allowlist environment variables passed to child processes.
- Acceptance:
  - Secrets are not inherited by default.

#### P2-4 Concurrency limits (DONE)

- Scope:
  - Enforce `spawn.max_concurrent`.
- Acceptance:
  - Burst spawns are rejected when above the limit.

- Tests (manual via `.test`):
  - Added:
    - `pascal/tests/spawn_cwd_jail_test.js`
    - `pascal/tests/spawn_env_scrub_test.js`
    - `pascal/tests/spawn_concurrency_limit_test.js`
    - `pascal/tests/spawn_profile_defaults_test.js`
  - Result:
    - `.test` passes: existing tests and all Phase 2 spawn policy tests.

### Phase 3 — Automation/daemon readiness (A-first, B-possible)

#### P3-1 Daemon orchestration with per-job isolation (DONE)

- Scope:
  - Support daemon mode but keep job execution isolated (new runtime/context per job).
- Acceptance:
  - Running many jobs does not accumulate state/handles.

- Tests (manual via `.test`):
  - Added:
    - `pascal/tests/daemon_isolation_test.js`
  - Result:
    - PASS

#### P3-2 HTTP policy (DONE)

- Scope:
  - Allowlist hosts, enforce timeouts and body size limits.
- Acceptance:
  - Requests outside policy fail deterministically.

- Tests (manual via `.test`):
  - Added:
    - `pascal/tests/http_policy_test.js`
  - Result:
    - PASS

#### P3-3 fs_watch policy (DONE)

- Scope:
  - Restrict watched roots and number of watchers; add throttling.
- Acceptance:
  - Watchers cannot be abused to exhaust resources.

- Tests (manual via `.test`):
  - Added:
    - `pascal/tests/fs_watch_policy_test.js`
  - Result:
    - PASS

---

## 6. Test Matrix (minimum)

### 6.1 Module loader

- Import `qjsp:` module resolution (libs preferred, runtime fallback).
- Import `lib:` with existing mount.
- Missing mount returns a clear error.
- Circular import produces a clear error.

### 6.2 Async/event loop correctness

- Promise microtasks complete after eval.
- Timers/async operations work without crashes.

### 6.3 Spawn sandbox (Windows)

- Kill-tree works (child processes terminated).
- Timeout enforced.
- Output limit enforced.
- CWD jail enforced.
- Concurrency limit enforced.

### 6.4 Daemon stability (if enabled)

- Run 500+ jobs sequentially: memory/handles stable.

---

## 7. Progress Tracking Template

Recommended Kanban columns:

- Backlog
- Ready
- In Progress
- Review
- Done

Ticket template:

- Goal
- Scope
- Acceptance criteria
- Test plan
- Risk & rollback

Definition of Done (DoD):

- Builds on Windows.
- Acceptance criteria met.
- Tests executed (automated or documented manual steps).
- Logging/error codes follow conventions.

---

## 8. Notes / Open Decisions

- Default REPL timeout and output limits must be chosen to remain usable.
- For Windows, Job Object integration is the preferred kill-tree mechanism.
- If future threat model requires stronger isolation, consider an out-of-process broker (Option 2).
