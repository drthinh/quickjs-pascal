# stdjs log

## Import

```js
import { log } from "qjsp:index.js";
```

## Logger

- `log.getLogger(name)` -> `Logger`
- `logger.setLevel("debug" | "info" | ... )`
- `logger.setSink(sink)`

Các method:

- `trace/debug/info/warn/error(message, context?)`

`context` là object tùy ý, sẽ được JSON stringify (có safe fallback).

## Sinks

- `log.consoleSink()` (mặc định)
- `log.fileSink(filename)` (append vào file bằng `qjs:std.open(..., "a")`)

Ví dụ:

```js
log.setDefaultLevel("debug");
const logger = log.getLogger("app");
logger.info("start", { pid: 123 });
logger.setSink(log.fileSink("./app.log"));
logger.warn("warning");
```
