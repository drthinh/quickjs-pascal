import * as std from "qjs:std";
import * as os from "qjs:os";
import { toU8 } from "qjsp:util/bytes.js";

export function exists(path) {
  const [st, err] = os.stat(String(path));
  return err === 0 && st != null;
}

export function stat(path) {
  const [st, err] = os.stat(String(path));
  if (err !== 0) return null;
  return st;
}

export function readTextFile(path) {
  const v = std.loadFile(String(path), { binary: true });
  if (v === null) throw new Error(`readTextFile: cannot read ${path}`);
  return new TextDecoder().decode(toU8(v));
}

export function readFile(path) {
  const v = std.loadFile(String(path), { binary: true });
  if (v === null) throw new Error(`readFile: cannot read ${path}`);
  return toU8(v);
}

export function writeTextFile(path, text) {
  const u8 = new TextEncoder().encode(String(text));
  std.writeFile(String(path), u8);
}

export function writeFile(path, data) {
  const u8 = toU8(data);
  std.writeFile(String(path), u8);
}

export function mkdir(path, mode) {
  const ret = os.mkdir(String(path), mode === void 0 ? 0o777 : mode);
  if (ret !== 0) throw new Error(`mkdir: failed ${path} (errno=${ret})`);
}

export function mkdirp(path, mode) {
  const p = String(path);
  if (p === "" || p === ".") return;
  if (exists(p)) return;

  const sep = p.indexOf("\\") >= 0 ? "\\" : "/";
  const parts = p.split(/[\\/]+/);
  let cur = "";

  if (/^[A-Za-z]:$/.test(parts[0])) {
    cur = parts.shift() + sep;
  } else if (p.startsWith("\\\\")) {
    cur = "\\\\";
  } else if (p.startsWith("/")) {
    cur = "/";
  }

  for (const part of parts) {
    if (!part || part === ".") continue;
    cur = cur ? (cur.endsWith(sep) ? cur + part : cur + sep + part) : part;
    if (!exists(cur)) mkdir(cur, mode);
  }
}

export function readdir(path) {
  const [arr, err] = os.readdir(String(path));
  if (err !== 0) throw new Error(`readdir: failed ${path} (errno=${err})`);
  return arr;
}

export function remove(path) {
  const ret = os.remove(String(path));
  if (ret !== 0) throw new Error(`remove: failed ${path} (errno=${ret})`);
}

export function rename(oldPath, newPath) {
  const ret = os.rename(String(oldPath), String(newPath));
  if (ret !== 0) throw new Error(`rename: failed (errno=${ret})`);
}
