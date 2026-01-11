import { os } from "qjsp:index.js";
import { spawn } from "qjsp:os/spawn.js";

function assert(cond, msg) {
  if (!cond) throw new Error(msg || "assert failed");
}

const platform = os.system.platform;
if (platform !== "win32") {
  console.log("stdjs spawn SIGINT ping test skipped (win32 only)");
} else {
  const p = spawn(["cmd.exe", "/C", "ping -t dantri.com.vn"], { inheritStdio: true, mergeStderr: true });

  // Note: don't use setTimeout() with waitSync(); waitSync blocks the JS thread.
  os.sleep(1000);
  p.kill(2);

  const r = p.waitSync();
  assert(!r || typeof r.code === "number", "waitSync should return {code:number} or undefined");
  console.log("stdjs spawn SIGINT ping test OK");
}
