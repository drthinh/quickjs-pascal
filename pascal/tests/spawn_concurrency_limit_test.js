import { os } from "qjsp:index.js";
import { spawn } from "qjsp:os/spawn.js";

function assert(cond, msg) {
  if (!cond) throw new Error(msg || "assert failed");
}

const platform = os.system.platform;

if (platform !== "win32") {
  console.log("spawn concurrency limit test skipped (win32 only)");
} else {
  const p1 = spawn(["cmd.exe", "/C", "ping 127.0.0.1 -n 30 >nul"], {
    mergeStderr: true,
    timeoutMs: 10000,
    maxOutputKb: 64,
  });

  let ok = false;
  try {
    spawn(["cmd.exe", "/C", "echo SECOND"], {
      mergeStderr: true,
      timeoutMs: 5000,
      maxOutputKb: 64,
    });
  } catch (e) {
    ok = true;
    assert(e && typeof e === "object", "expected error object");
    assert(e.code === "QJSP_E_SPAWN_CONCURRENCY_LIMIT", "expected QJSP_E_SPAWN_CONCURRENCY_LIMIT");
  }

  try {
    p1.kill(9);
  } catch (e) {
  }

  const r1 = p1.waitSync();
  assert(r1 && typeof r1 === "object", "waitSync() should return an object");
  assert(ok, "expected spawn to be denied by concurrency limit");
  console.log("spawn concurrency limit test OK");
}
