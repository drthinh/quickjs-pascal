import { log } from "qjsp:index.js";

log.setDefaultLevel("debug");

const a = log.getLogger("a");
a.debug("hello", { x: 1 });

const sink = log.fileSink("./.qjsp_log_test.log");
a.setSink(sink);
a.info("file log line", { ok: true });

console.log("stdjs log test OK");
