# QAR v2 Specification (Design + Checklist)

## 1) Goals

- Define a **QAR v2 binary format** that fixes v1 issues:
  - Fast lookup (avoid `O(n)` linear scan per import).
  - Stable **path semantics** (canonicalization rules).
  - Better robustness (bounds checks, decompression limits).
  - Extensible layout (sections + versioning).
  - Real integrity validation (hash/signature) instead of relying on compression.
- Keep **zlib** as the compression codec.
- **Verification policy**:
  - If the archive contains a signature: default verify mode is **strict**.
  - If the archive has no signature: default verify mode is **warn**.

## 2) Non-goals

- Not a ZIP-compatible format.
- Not intended to support in-place editing; rebuild is the expected workflow.
- Not defining a cross-language standard beyond this repo’s Pascal implementation.

## Implementation status (repo progress)

### Completed

- **REPL tooling**
  - `.build` supports `--v1`, `--v2`, `--format N` and forwards to `qar.BuildQar(..., format_version)`.
  - `.qar build` supports `--v1`, `--v2`, `--format N` (options can appear before/after output).
  - `.qar info <file>` reports archive format by inspecting the file magic (`QAR\x01` vs `QAR\x02`).
  - Help/menu updated to document format selection options.

- **Writer v2 (minimal but functional)**
  - Writes v2 header + section table.
  - Sections emitted: `PATH`, `ENTR`, `DATA`, `INDEX`, `MANF`.
  - `MANF` now contains JSON metadata including `quickjs_version`, optional build metadata, and signature block fields.
  - `sig_payload_b64` is now included in `MANF` when signature info is present.

- **Reader v2 (minimal but functional)**
  - Loader branches by magic and parses v2 via section table.
  - Parses `PATH`, `ENTR`, `DATA` offsets, `INDEX`.
  - Reads `MANF` (if present) and exposes `qar_get_manifest` / `qar_get_quickjs_version`.

- **Inspection tooling**
  - `.qar inspect` detects v2 compression status from v2 entry metadata (not v1 layout parsing).

### Known gaps / next steps

- **SIGN section**
  - `SIGN` section is still omitted (placeholder). Signature verification is currently manifest-based only.

- **Manifest schema & verification**
  - `MANF` is JSON; loader extraction uses lightweight parsing for `quickjs_version`.
  - Full validation of manifest fields and schema evolution rules still TODO.

- **Compression policy**
  - Current compression behavior depends on builder heuristics; no “force compress” option yet.

- **Full v2 spec coverage**
  - Remaining robustness/verification policy details (limits, strict checks, unknown sections) should be audited against this document.

---

## 3) File model: header + section table

QAR v2 is a **sectioned** container:

- Header (fixed size)
- Section table (list of sections)
- Section payloads (PATH/INDEX/ENTR/DATA/MANF/SIGN/…)

### 3.1 Magic / versioning

- v1 magic: `"QAR\x01"`
- v2 magic: `"QAR\x02"`

The loader must branch early:

- If magic is v1 => parse with v1 reader.
- If magic is v2 => parse via section table.

### 3.2 Header (recommended fields)

Little-endian, fixed header size (example 64 bytes):

- `magic[4]`: `QAR\x02`
- `format_major` (u16): 2
- `format_minor` (u16): 0
- `header_size` (u32)
- `flags` (u32)
- `section_count` (u32)
- `section_table_offset` (u64)
- `section_table_size` (u64)
- `archive_size` (u64)
- `reserved[...]`

### 3.3 Section table

Each section record:

- `type` (u32)
- `flags` (u32)
- `offset` (u64)
- `size` (u64)

Forward-compat rule: unknown `type` must be skipped.

---

## 4) Standard sections

### 4.1 `PATH` (path string table)

Stores UTF-8 path strings (canonical). The archive stores **path ids** rather than repeating strings.

### 4.2 `ENTR` (entry metadata)

Fixed-size array of entry records.

Recommended entry fields:

- `path_id` (u32)
- `kind` (u8): script/module/asset
- `codec_bc` (u8): 0=none, 1=zlib
- `codec_src` (u8): 0=none, 1=zlib
- `flags` (u8): has_bytecode/has_source/etc.
- `bc_offset` (u64) / `bc_size_comp` (u64) / `bc_size_orig` (u64)
- `src_offset` (u64) / `src_size_comp` (u64) / `src_size_orig` (u64)
- `sha256_bc[32]` (optional but recommended)
- `sha256_src[32]` (optional but recommended)

### 4.3 `DATA` (payload blobs)

Contains the compressed or raw payload blobs referenced by `ENTR` offsets.

Recommended: store payload as chunked blocks with small headers so the loader can validate bounds and codec per-block.

### 4.4 `INDEX` (path lookup index)

Provides fast mapping from `canonical_path` to `entry_index`.

Recommended design:

- Hash table (open addressing).
- Key: 64-bit hash of canonical path.
- Value: `entry_index`.
- Collision resolution: compare canonical strings from `PATH`.

### 4.5 `MANF` (manifest JSON)

UTF-8 JSON for metadata:

- `format`, `version`
- `quickjs_version`
- optional build metadata
- optional `entry_points`

Manifest is treated as metadata; loader must not rely on fragile substring scanning.

### 4.6 `SIGN` (signature block)

Separate from manifest.

- `alg`: `ed25519`
- `pubkey`: bytes/base64
- `sig`: bytes/base64
- `signed_payload`: definition of what is signed (see Integrity section)

---

## 5) Canonical path rules (MUST)

Canonicalization is applied:

- At build time (every stored entry path).
- At lookup time (requested module path before searching the index).

Rules:

- Separator: convert `\` to `/`.
- No leading `/`.
- Remove `.` segments.
- Resolve `..` segments by popping; if it escapes root => reject.
- No NUL, no control characters.
- UTF-8.
- Case: preserve original case. If Windows needs case-insensitive behavior, implement it as an option in the loader lookup policy (not baked into stored paths).

---

## 6) Compression (zlib)

- Codec id: `1 = zlib`.
- Compression is per payload (bytecode/source/asset) and explicitly stored in `ENTR` (`codec_bc`, `codec_src`).

Robustness requirements:

- Enforce maximum `orig_size` limits to prevent zip bombs.
- Validate `offset + size <= archive_size` before reading.

---

## 7) Integrity & verification

### 7.1 Per-entry hashes

Recommended: store `sha256` of **uncompressed** bytecode/source in `ENTR`.

Verify logic:

- When loading an entry, after decompressing, hash and compare.

### 7.2 Signature

Recommended signature payload includes:

- Header fields relevant to layout (format version, section table location).
- `PATH` bytes + `ENTR` bytes + `MANF` bytes.
- Either:
  - Hashes of `DATA` blocks, or
  - The per-entry sha256 values from `ENTR` (preferred to avoid signing huge `DATA`).

### 7.3 Default verify mode policy

- If `SIGN` section exists => default verify mode is **strict**.
- If no `SIGN` => default verify mode is **warn**.

User override should remain possible (e.g., CLI `--verify off|warn|strict`).

---

## 8) Compatibility rules

### 8.1 Backward compatibility (v2 loader)

Loader v2 must support:

- Reading v1 (`QAR\x01`) exactly as today (with added robustness checks).
- Reading v2 (`QAR\x02`) via sections.

### 8.2 Forward compatibility

- Loader v2 must skip unknown section types.
- `MANF` schema can evolve (new fields) without breaking loader.

### 8.3 Builder output

Builder should support:

- Output format v1 or v2 (explicit option).
- Default output can be v2.

---

## 9) Migration strategy

Provide a conversion workflow:

- `v1 -> v2` by rebuilding:
  - Read v1 entries.
  - Apply canonical path rules.
  - Repack into v2 with `PATH/ENTR/DATA/INDEX/MANF`.
  - Optionally sign into `SIGN`.

---

## 10) Implementation checklist

### 10.1 Format + parsing

- [ ] Define v2 magic and header constants.
- [ ] Implement section table reader with full bounds checking.
- [ ] Implement `PATH` reader (string table) and `path_id -> string` resolver.
- [ ] Implement `ENTR` reader and validation:
  - [ ] `offset + size <= archive_size` for each payload.
  - [ ] size limits for compressed/uncompressed.
- [ ] Implement `DATA` block reader (random access reads).

### 10.2 Index

- [ ] Implement `INDEX` build (hash table) in builder.
- [ ] Implement `INDEX` load + lookup in loader.
- [ ] Enforce canonical path normalization in lookup.
- [ ] Remove/avoid basename fallback behaviors in v2 path policy.

### 10.3 Compression (zlib)

- [ ] Standardize codec ids (`0=none`, `1=zlib`).
- [ ] Add hard limits:
  - [ ] Max entry count.
  - [ ] Max per-entry `orig_size`.
  - [ ] Max total decompressed bytes per runtime session (optional).

### 10.4 Signing + verification

- [ ] Define signed payload format for v2.
- [ ] Emit `SIGN` section when signing.
- [ ] Loader verification:
  - [ ] If `SIGN` exists: default verify = strict.
  - [ ] If not: default verify = warn.
  - [ ] Override via CLI/config remains supported.
- [ ] Verify per-entry sha256 on load (strict/warn behavior).

### 10.5 Tooling & inspection

- [ ] Update `.qar inspect` output:
  - [ ] Report v1 vs v2.
  - [ ] Dump sections list.
  - [ ] Show whether signed, and verify result.
- [ ] Add `convert` / `rebuild-to-v2` workflow.

### 10.6 Tests

- [ ] Golden files:
  - [ ] One v1 sample.
  - [ ] One v2 sample.
  - [ ] Signed v2 sample.
- [ ] Negative/corrupt tests:
  - [ ] Truncated file.
  - [ ] Bad offsets.
  - [ ] Huge orig_size (zip bomb prevention).
  - [ ] Hash mismatch (warn vs strict).
- [ ] Perf tests:
  - [ ] Many entries (e.g. 10k) lookup timing.
  - [ ] Startup import chain timing.

---

## 11) Notes (repo context)

- QAR is implemented in Pascal in this repo.
- Existing docs:
  - `qar_structure.md` (v1 layout)
  - `qar_signing.md` (Ed25519 key formats + signing usage)

This document defines the **v2 format** and the **implementation checklist**.
