import { time, concurrent } from "qjsp:index.js";

const { Instant, Duration } = time;

const t0 = Instant.now();
await concurrent.sleep(10);
const t1 = Instant.now();

const d = Duration.between(t0, t1);
if (d.toMillis() < 0) throw new Error("Duration.between negative");

// deferred + withTimeout
const dfd = concurrent.deferred();
setTimeout(() => dfd.resolve("ok"), 10);

const v = await concurrent.withTimeout(dfd.promise, 100);
if (v !== "ok") throw new Error("deferred/withTimeout failed");

console.log("stdjs time+concurrent test OK");
