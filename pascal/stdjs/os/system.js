import * as std from "qjs:std";
import * as os from "qjs:os";
import * as env from "qjsp:os/env.js";

export const platform = typeof os.platform === "string" ? os.platform : "unknown";

export const arch = (() => {
  const a = env.get("PROCESSOR_ARCHITECTURE", env.get("HOSTTYPE", env.get("MACHTYPE", void 0)));
  if (a) return String(a).toLowerCase();
  return "unknown";
})();

export const hostname = (() => {
  const v = env.get("COMPUTERNAME", env.get("HOSTNAME", void 0));
  if (v) return String(v);
  if (typeof std.popen === "function") {
    try {
      const f = std.popen("hostname", "r");
      const out = f.readAsString();
      f.close();
      const s = String(out).trim();
      if (s) return s;
    } catch (e) {
    }
  }
  return "";
})();

export function homedir() {
  if (platform === "win32") {
    const v = env.get("USERPROFILE", void 0);
    if (v) return String(v);
    const hd = env.get("HOMEDRIVE", void 0);
    const hp = env.get("HOMEPATH", void 0);
    if (hd && hp) return String(hd) + String(hp);
  }
  const v = env.get("HOME", void 0);
  return v ? String(v) : "";
}

export function tmpdir() {
  const v = env.get("TMPDIR", env.get("TEMP", env.get("TMP", void 0)));
  return v ? String(v) : (platform === "win32" ? "C:\\Windows\\Temp" : "/tmp");
}
