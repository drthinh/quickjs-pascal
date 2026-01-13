import { io, os } from "qjsp:index.js";

function assert(cond, msg) {
  if (!cond) throw new Error(msg || "assert failed");
}

function assertString(v, msg) {
  assert(typeof v === "string", msg || "expected string");
}

function assertHostError(e, expectedCode) {
  assert(e && typeof e === "object", "expected error object");
  assertString(e.code, "expected error.code string");
  assertString(e.name, "expected error.name string");
  assertString(e.message, "expected error.message string");
  if (expectedCode !== void 0) assert(e.code === expectedCode, `expected code ${expectedCode}`);
  assert(e.name === "HostError", "expected HostError.name");
  if (typeof e.stack === "string") assert(e.stack.length >= 0, "expected stack string");
}

function getErrCode(e) {
  try {
    return e && typeof e === "object" ? e.code : void 0;
  } catch (_) {
    return void 0;
  }
}

const platform = os.system.platform;

if (platform !== "win32") {
  console.log("fs_watch policy test skipped (win32 only)");
} else {
  const { fs, path } = io;

  const base = "./tests/tmp/fs_watch_policy";
  fs.rmrf(base);
  fs.mkdirp(base);

  // Root deny: watch outside allowed root (tests/tmp)
  {
    let ok = false;
    try {
      fs.watch(".", () => {});
    } catch (e) {
      assertHostError(e, "QJSP_E_FSWATCH_ROOT_DENIED");
      ok = getErrCode(e) === "QJSP_E_FSWATCH_ROOT_DENIED";
    }
    assert(ok, "expected root deny when watching '.'");
  }

  // Allowed dir: under tests/tmp
  const dir1 = path.resolve(base);
  const w1 = fs.watch(dir1, () => {}, { recursive: true });

  // Max watchers is 1 in config, so second watcher should fail
  {
    let ok = false;
    try {
      fs.watch(dir1, () => {}, { recursive: true });
    } catch (e) {
      assertHostError(e, "QJSP_E_FSWATCH_LIMIT");
      ok = getErrCode(e) === "QJSP_E_FSWATCH_LIMIT";
    }
    assert(ok, "expected max watchers limit");
  }

  w1.close();
  fs.rmrf(base);
  console.log("fs_watch policy test OK");
}
