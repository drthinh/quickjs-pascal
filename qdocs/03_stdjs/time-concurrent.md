# stdjs time + concurrent

## Import

```js
import { time, concurrent } from "qjsp:index.js";
const { Instant, Duration } = time;
```

## time

- `Instant.now()`
- `Instant.fromEpochMs(ms)`
- `Instant#toISOString()`
- `Duration.ofMillis(ms)`, `Duration.ofSeconds(sec)`
- `Duration.between(startInstant, endInstant)`

## concurrent

- `concurrent.deferred()` -> `{ promise, resolve, reject }`
- `concurrent.sleep(ms)` -> Promise
- `concurrent.withTimeout(promise, ms, makeError?)`

Ví dụ:

```js
const dfd = concurrent.deferred();
setTimeout(() => dfd.resolve("ok"), 10);
const v = await concurrent.withTimeout(dfd.promise, 100);
```
