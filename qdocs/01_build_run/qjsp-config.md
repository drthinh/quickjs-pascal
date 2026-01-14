# qjsp config (persist settings)

Tài liệu này mô tả cơ chế config persistent của host `qjsp` (Pascal) và một số runtime settings của QuickJS engine.

## 1. File config mặc định

`qjsp` lưu config local tại:

- `config/qjsp_config.json`

Vị trí này được resolve dựa trên executable của `qjsp` (portable/local). Logic hiện tại:

- Ưu tiên `pascal_root/config/qjsp_config.json` (tức thư mục `config/` nằm cạnh `src/` khi chạy từ tree)
- Fallback: `./config/qjsp_config.json`
- Fallback: `<exe_dir>/config/qjsp_config.json`

Bạn có thể override bằng CLI:

- `qjsp --config <path/to/config.json>`

## 2. Auto-load / auto-save

- Khi `qjsp` khởi động, nó sẽ **auto-load** block `settings` từ file config (nếu có).
- Khi thoát REPL (`exit/quit/.exit/.quit`) `qjsp` sẽ **auto-save** lại `settings` **nếu có thay đổi** trong phiên (`config_dirty = true`).

Lưu ý về ưu tiên:

- CLI flags vẫn có thể override giá trị đã load từ config trong phiên chạy hiện tại.
- Mặc định, việc override bằng CLI **không tự ghi ngược** vào config trừ khi bạn thay đổi qua `.config ...` (và/hoặc gọi `.config save`).

## 3. Schema trong `qjsp_config.json`

`qjsp_config.json` có thể chứa nhiều block khác nhau. Phần liên quan tới persist settings nằm ở:

- `settings` (object)

Ví dụ:

```json
{
  "config_version": 1,
  "settings": {
    "debug_level": 1,
    "log_timestamp": true,
    "guard": "friendly",
    "mode": "",
    "dump_flags": 32
  },
  "libraries": {
    "lib": "libs"
  }
}
```

Các field trong `settings`:

- `debug_level` (0..4)
  - Điều khiển log ở tầng Pascal và một số runtime debug behavior.
- `log_timestamp` (boolean)
  - Bật/tắt timestamp cho log host.
- `guard` (`"strict" | "friendly"`)
  - Chế độ bảo vệ REPL khi có lỗi nghiêm trọng (ví dụ access violation).
- `mode` (string)
  - Tên REPL mode mặc định (ví dụ `"sh"`).
  - Nếu rỗng hoặc không có key này thì mode mặc định là off.
- `dump_flags` (number)
  - Dump flags của QuickJS (bitmask), dùng cho debug engine.
  - Nếu key này tồn tại (kể cả bằng 0) thì được coi là “explicit”.

## 4. Lệnh `.config` trong REPL

Trong REPL, dùng lệnh `.config` để xem/chỉnh/persist settings.

### 4.1. Xem trạng thái

- `.config show`

In ra file config đang dùng và các giá trị `settings.*` đang active.

Lưu ý:

- `settings.dump` được in dạng `on/off` dựa trên trạng thái “explicit dump flags” trong phiên (không in số bitmask).

### 4.2. Set giá trị

Cú pháp:

- `.config set <key> <value>`

Các key hỗ trợ:

- `debug`:
  - `.config set debug 0|1|2|3|4`
- `ts` / `timestamp`:
  - `.config set ts on|off`
- `guard`:
  - `.config set guard strict|friendly`
- `mode`:
  - `.config set mode sh`
- `dump`:
  - `.config set dump 0`
  - `.config set dump off`
  - `.config set dump on`
  - `.config set dump <number>`

### 4.3. Unset (xóa khỏi settings)

- `.config unset mode`
  - Tắt mode mặc định.
- `.config unset dump` (hoặc `dump_flags`)
  - Không còn “explicit dump_flags” trong config.
- `.config unset guard`
  - Bỏ trạng thái “explicit guard” (không persist guard vào config nữa).
  - Guard mode đang active trong phiên không nhất thiết bị đổi ngay; nó chỉ không còn được coi là “explicit” để ghi ra file.

### 4.4. Lưu ngay

- `.config save`

Ghi `settings` hiện tại ra `qjsp_config.json`.

### 4.5. Reload từ file

- `.config reload`

Đọc lại `settings` từ file config và áp dụng lại vào phiên hiện tại.

### 4.6. Reset về default (chưa lưu)

- `.config reset`

Reset các giá trị về default trong memory (chưa ghi ra file cho đến khi `.config save` hoặc thoát REPL và auto-save).

## 5. Ví dụ workflow

### 5.1. Bật debug và dump GC, lưu lại cho lần sau

```text
js> .config set debug 1
js> .config set dump 32
js> .config save
js> .exit
```

### 5.2. Bật mode shell mặc định

```text
js> .config set mode sh
js> .config save
```

Lần sau chạy lại `qjsp`, REPL sẽ tự vào `sh` mode (nếu mode đó có sẵn trong config `repl_modes`).

## 6. Liên quan tới các block khác

Ngoài `settings`, `qjsp_config.json` còn được dùng cho:

- `libraries`: các mounts cho module loader (xem `.lib ...`).
- `tests` / `examples`: danh sách test enable/disable (xem `.test ...`).

Ngoài ra file config còn có thể chứa các block policy/runtime khác (tùy build), ví dụ:

- `spawn`: policy cho module spawn (`qjsp:os/spawn.js`).
- `http`: policy cho HTTP helpers.
- `fs_watch`: policy cho filesystem watcher.

Xem thêm:

- `daemon-mode.md` (daemon runner và test isolation)
- `../03_stdjs/sh.md` và `repl-sh-editor.md` (shell mode + editor)

## 7. Ghi chú dump flags

Nếu bạn set `dump_flags` khác 0 nhưng đọc lại vẫn ra 0, nhiều khả năng `libqjs` đang build không bật `ENABLE_DUMPS`.

Xem thêm:

- `dump-flags.md`
