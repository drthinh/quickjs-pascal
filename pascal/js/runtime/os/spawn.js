import * as system from "qjsp:os/system.js";
import * as native from "qjsp:os/spawn/native";

function _shellArgv(command) {
  const cmd = String(command);
  if (system.platform === "win32") {
    return ["cmd.exe", "/C", cmd];
  }
  return ["sh", "-c", cmd];
}

export function spawn(argv, opts) {
  const r = native.spawn(argv, opts);
  const id = r && typeof r.id === "number" ? r.id : (r && typeof r.id === "bigint" ? Number(r.id) : null);
  if (id == null) throw new Error("spawn: native returned invalid id");
  const pid = r && typeof r.pid === "number" ? r.pid : (r && typeof r.pid === "bigint" ? Number(r.pid) : 0);

  return {
    id,
    pid,
    wait() {
      return native.waitAsync(id);
    },
    waitSync() {
      return native.wait(id);
    },
    kill(sig) {
      return native.kill(id, sig);
    },
  };
}

export function spawnShell(command, opts) {
  return spawn(_shellArgv(command), { ...(opts && typeof opts === "object" ? opts : {}), shell: true });
}

export function spawnp(command, opts) {
  const p = spawnShell(command, opts);
  const r = p.waitSync();
  return r && typeof r.code === "number" ? r.code : 0;
}
