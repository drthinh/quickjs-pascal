import { os } from "qjsp:index.js";
import { spawn } from "qjsp:os/spawn.js";

function assert(cond, msg) {
  if (!cond) throw new Error(msg || "assert failed");
}

const platform = os.system.platform;

if (platform !== "win32") {
  console.log("spawn cwd jail test skipped (win32 only)");
} else {
  let ok = false;
  try {
    spawn(["cmd.exe", "/C", "echo OK"], {
      mergeStderr: true,
      timeoutMs: 5000,
      maxOutputKb: 64,
      cwd: "C:\\Windows",
    });
  } catch (e) {
    ok = true;
    assert(e && typeof e === "object", "expected error object");
    assert(e.code === "QJSP_E_SPAWN_CWD_DENIED", "expected QJSP_E_SPAWN_CWD_DENIED");
  }
  assert(ok, "expected spawn to be denied by CWD jail");
  console.log("spawn cwd jail test OK");
}
