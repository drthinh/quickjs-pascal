import * as std from "qjs:std";
import * as os from "qjs:os";

function quoteArgWin(s) {
  const v = String(s);
  if (v === "") return '""';
  if (!/[\s"]/g.test(v)) return v;
  return '"' + v.replace(/"/g, '\\"') + '"';
}

function quoteArgPosix(s) {
  const v = String(s);
  if (v === "") return "''";
  if (!/[\s'"\\$`]/.test(v)) return v;
  return "'" + v.replace(/'/g, "'\\''") + "'";
}

function quoteArg(s) {
  const isWin = typeof os.platform === "string" && os.platform === "win32";
  return isWin ? quoteArgWin(s) : quoteArgPosix(s);
}

export function exec(command) {
  if (typeof std.popen !== "function") {
    if (typeof os.exec === "function") {
      const code = os.exec([String(command)]);
      return { stdout: "", code };
    }
    throw new Error("exec: std.popen/os.exec not available");
  }

  const f = std.popen(String(command), "r");
  const stdout = f.readAsString();
  const rc = f.close();
  return { stdout, code: rc };
}

export function execFile(file, args, opts) {
  const a = Array.isArray(args) ? args : [];
  const o = opts && typeof opts === "object" ? opts : {};

  const cmd = [String(file), ...a.map(quoteArg)].join(" ");
  if (o && o.shell) {
    return exec(cmd);
  }

  if (typeof os.exec === "function") {
    const code = os.exec([String(file), ...a.map(String)]);
    return { stdout: "", code };
  }

  if (typeof std.popen === "function") {
    return exec(cmd);
  }

  throw new Error("execFile: std.popen/os.exec not available");
}
