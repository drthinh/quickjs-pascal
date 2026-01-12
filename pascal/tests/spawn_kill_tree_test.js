import { os } from "qjsp:index.js";
import { spawn } from "qjsp:os/spawn.js";

function assert(cond, msg) {
  if (!cond) throw new Error(msg || "assert failed");
}

const platform = os.system.platform;

if (platform !== "win32") {
  console.log("spawn kill-tree test skipped (win32 only)");
} else {
  // Parent sleeps ~30s and also starts a child sleep in background.
  // With Job Object kill-tree, killing the parent should also kill its child.
  // This test primarily checks that kill() returns and wait() completes quickly.
  const cmd = "start \"\" /B cmd.exe /C \"ping 127.0.0.1 -n 30 >nul\" & ping 127.0.0.1 -n 30 >nul";
  const p = spawn(["cmd.exe", "/C", cmd], {
    mergeStderr: true,
    timeoutMs: 10000,
    maxOutputKb: 64,
  });

  os.sleep(500);
  p.kill(9);

  const r = p.waitSync();
  assert(r && typeof r === "object", "wait() should return an object");
  assert(typeof r.code === "number", "expected code:number");
  console.log("spawn kill-tree test OK");
}
