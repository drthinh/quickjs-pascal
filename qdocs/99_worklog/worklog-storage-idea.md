# WORKLOG STORAGE (IDEA ONLY)

Status: **idea / concept only** (no implementation yet)

## Goal

Persist the results of a working session over time (commands, logs, messages, results, exceptions, fetched web content) while keeping it easy to:

- Search by metadata (time range, session, type, level, source, tag/project)
- Search by content (keywords/phrases inside logs/output/message/result)
- Support CRUD (create/update/delete sessions or events)
- Clean up old data when storage grows

## Why SQLite

SQLite is a good fit because it provides:

- A single portable file (`.db`) for storage and backup
- Transactions and data integrity
- Indexes for fast filtering by metadata
- Optional full-text search (FTS5) for large text content

## Core model: Session + Event timeline

### Sessions
A session is a container for one working run.

**Proposed fields** (example):

- `id`
- `title`
- `started_at`, `ended_at`
- `cwd` / `project`
- `status` (ok/error/killed)

Optional:

- `tags` (either as a separate `session_tags` table, or stored as text/JSON)

### Events (append-only timeline)
Store each step in the session as one event row. This matches how interactive work happens and makes replay/auditing possible.

**Typical event types**:

- `command` (user input)
- `log` (stdout/stderr, engine logs)
- `message` (system/UI message)
- `result` (evaluated result)
- `exception` (error + stack)
- `fetch` (web fetch result)

**Proposed fields** (example):

- `id`
- `session_id`
- `ts` (timestamp)
- `seq` (monotonic sequence within a session for stable ordering)
- `type` (command/log/message/result/exception/fetch/...)
- `level` (debug/info/warn/error)
- `source` (user/stdout/stderr/engine/web/...)
- `text` (main text content)
- `json` (extra structured metadata: url, http_status, elapsed_ms, exit_code, stacktrace, headers, etc.)

Rationale for both `text` and `json`:

- `text` is good for display and full-text search
- `json` keeps the schema flexible (events are heterogeneous)

## Searching “all possible ways”

### 1) Metadata filtering (fast via indexes)
Examples:

- Events by `session_id`
- Events in a time range (`ts`)
- Events by `type`/`level` (e.g. only error logs)
- Sessions by `project`/`status`/`tag`

**Index ideas**:

- `events(session_id, seq)`
- `events(ts)`
- `events(type, level)`
- `sessions(started_at)`

### 2) Full-text search (FTS5) on content
Use SQLite FTS5 for searching inside `events.text`.

Examples:

- Find occurrences of `AccessViolation`
- Find where `.reload` was used
- Find errors containing `timeout`

### 3) Combined queries (filter + full-text)
Examples:

- Search `timeout` only in `type='log'` and `level='error'`
- Search within last 7 days only
- Search within one specific session only

## English logs + Vietnamese content

- Logs/commands are mostly English: default FTS tokenization works well.
- Fetched web content may include Vietnamese:
  - FTS5 still works for keyword search.
  - Tokenization quality for Vietnamese “word” boundaries is not perfect (Vietnamese uses spaces between syllables), but it is often acceptable for practical keyword search.
  - If advanced Vietnamese search is needed later, consider specialized tokenization/normalization as a future enhancement.

## Handling unknown / potentially large payload sizes

Because the event count and per-event size are unknown up front, keep an “escape hatch” for large payloads.

Two storage strategies:

- Store normal-sized text in `events.text`.
- For very large outputs (MBs): store content as an external artifact file and keep references in `events.json`:
  - `path`, `sha256`, `size`, `content_type`, optional `preview`

This keeps the DB responsive and backups manageable.

## Delete / update policy (concept)

- Delete a session: remove all events for `session_id` (optionally cascade).
- Update an event:
  - Simple approach: update the row.
  - Audited approach: append a new `edit` event referencing the old one.
- Cleanup: delete sessions/events older than a cutoff date.

## Non-goals (for now)

- No implementation details or code changes yet.
- No decision yet on exact table DDL or Pascal integration.

## Next (if/when implementing)

- Choose a stable schema and migration strategy.
- Decide whether to store large payloads in DB or as external artifacts.
- Implement a minimal API: create session, append event, query (filter + FTS), delete session.
