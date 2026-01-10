import * as std from "qjs:std";
import * as os from "qjs:os";

function getArgv() {
  if (Array.isArray(globalThis.scriptArgs)) return globalThis.scriptArgs.slice();
  if (Array.isArray(globalThis.args)) return globalThis.args.slice();
  return [];
}

export const argv = getArgv();

export function cwd() {
  if (typeof os.getcwd !== "function") return ".";
  const v = os.getcwd();
  if (Array.isArray(v)) {
    const path = v[0];
    const err = v[1];
    if (typeof err === "number" && err !== 0) {
      throw new Error(`cwd: failed (errno=${err})`);
    }
    return String(path);
  }
  return String(v);
}

export function chdir(path) {
  if (typeof os.chdir !== "function") throw new Error("chdir: os.chdir not available");
  const ret = os.chdir(String(path));
  if (ret !== 0) throw new Error(`chdir: failed (errno=${ret})`);
}

export function exit(code) {
  if (typeof std.exit !== "function") throw new Error("exit: std.exit not available");
  std.exit(code === void 0 ? 0 : code);
}

export function sleep(ms) {
  const v = Number(ms);
  if (!Number.isFinite(v) || v < 0) return;
  if (typeof os.sleep === "function") {
    os.sleep(v / 1000);
    return;
  }
  if (typeof os.usleep === "function") {
    os.usleep(Math.floor(v * 1000));
    return;
  }
  throw new Error("sleep: os.sleep/os.usleep not available");
}
