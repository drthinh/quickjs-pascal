import { os } from "qjsp:index.js";
import { spawn } from "qjsp:os/spawn.js";

function assert(cond, msg) {
  if (!cond) throw new Error(msg || "assert failed");
}

const platform = os.system.platform;

if (platform !== "win32") {
  console.log("spawn timeout test skipped (win32 only)");
} else {
  const p = spawn(["cmd.exe", "/C", "ping 127.0.0.1 -n 30 >nul"], {
    mergeStderr: true,
    timeoutMs: 300,
    maxOutputKb: 64,
  });

  const r = p.waitSync();
  assert(r && typeof r === "object", "wait() should return an object");
  assert(r.timedOut === true, "expected timedOut=true");
  assert(typeof r.code === "number", "expected code:number");
  console.log("spawn timeout test OK");
}
