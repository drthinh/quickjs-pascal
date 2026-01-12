import { os } from "qjsp:index.js";
import { spawn } from "qjsp:os/spawn.js";

function assert(cond, msg) {
  if (!cond) throw new Error(msg || "assert failed");
}

const platform = os.system.platform;

if (platform !== "win32") {
  console.log("spawn output limit test skipped (win32 only)");
} else {
  const spam = "for /L %i in (1,1,5000) do @echo 0123456789012345678901234567890123456789";
  const p = spawn(["cmd.exe", "/C", spam], {
    mergeStderr: true,
    timeoutMs: 10000,
    maxOutputKb: 8,
  });

  const r = p.waitSync();
  assert(r && typeof r === "object", "wait() should return an object");
  assert(r.truncated === true, "expected truncated=true");
  assert(typeof r.code === "number", "expected code:number");
  console.log("spawn output limit test OK");
}
