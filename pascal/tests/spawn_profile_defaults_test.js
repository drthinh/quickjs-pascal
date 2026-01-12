import { os } from "qjsp:index.js";
import { spawn } from "qjsp:os/spawn.js";

function assert(cond, msg) {
  if (!cond) throw new Error(msg || "assert failed");
}

const platform = os.system.platform;

if (platform !== "win32") {
  console.log("spawn profile defaults test skipped (win32 only)");
} else {
  // In prod_automation profile, host defaults should be stricter.
  // This test assumes config has settings.profile = "prod_automation" and spawn.timeout_ms_default ~= 5000.
  const p = spawn(["cmd.exe", "/C", "ping 127.0.0.1 -n 30 >nul"], {
    mergeStderr: true,
  });

  const r = p.waitSync();
  assert(r && typeof r === "object", "waitSync() should return an object");
  assert(r.timedOut === true, "expected timedOut=true under prod profile defaults");
  console.log("spawn profile defaults test OK");
}
