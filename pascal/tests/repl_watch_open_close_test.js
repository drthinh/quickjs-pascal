import { io, os } from "qjsp:index.js";

function assert(cond, msg) {
  if (!cond) throw new Error(msg || "assert failed");
}

const platform = os.system.platform;

if (platform !== "win32") {
  console.log("repl watch open/close test skipped (win32 only)");
} else {
  const { fs, path } = io;

  const base = "./tests/tmp/repl_watch_open_close";
  fs.rmrf(base);
  fs.mkdirp(base);

  const dir1 = path.resolve(base);
  const before = globalThis.__qjspWatchCount | 0;
  const w = fs.watch(dir1, () => {}, { recursive: true });
  const mid = globalThis.__qjspWatchCount | 0;

  w.close();
  const after = globalThis.__qjspWatchCount | 0;

  assert(mid >= before, "expected watch count to not decrease after watch()");
  assert(after <= mid, "expected watch count to not increase after close()");

  fs.rmrf(base);
  console.log("repl watch open/close test OK", JSON.stringify({ before, mid, after }));
}
