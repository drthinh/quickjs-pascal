import { EventEmitter } from "qjsp:events/EventEmitter.js";
import * as q from "qjsp:index.js";
import * as osw from "qjsp:os/index.js";

const ee = new EventEmitter();
let c = 0;

ee.on("a", () => c++);
ee.emit("a");
ee.emit("a");

if (c !== 2) throw new Error("EventEmitter failed");

if (!q.events) throw new Error("qjsp:index.js missing events");
if (!q.os) throw new Error("qjsp:index.js missing os");

if (typeof osw.process.cwd !== "function") throw new Error("os.process.cwd missing");

const cwd = osw.process.cwd();
if (typeof cwd !== "string") throw new Error("cwd must be string");

"ok";
