import * as std from "qjs:std";
import * as os from "qjs:os";
import { toU8 } from "qjsp:util/bytes.js";
import * as path from "qjsp:io/path.js";
import * as system from "qjsp:os/system.js";
import { acquirePump, releasePump } from "qjsp:runtime/pump.js";
import { QjspError, requireNative } from "qjsp:runtime/error.js";

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
  if (v === null) throw new QjspError("QJSP_E_IO_READ_FAILED", `readTextFile: cannot read ${path}`, { path: String(path) });
  return new TextDecoder().decode(toU8(v));
}

export function readFile(path) {
  const v = std.loadFile(String(path), { binary: true });
  if (v === null) throw new QjspError("QJSP_E_IO_READ_FAILED", `readFile: cannot read ${path}`, { path: String(path) });
  return toU8(v);
}

export function writeTextFile(filePath, text) {
  const u8 = new TextEncoder().encode(String(text));
  let p = String(filePath);
  if (system.platform === "win32") {
    p = p.replace(/\//g, "\\");
    p = path.resolve(p);
    p = p.replace(/\//g, "\\");
  }
  try {
    mkdirp(path.dirname(p));
  } catch (e) {
  }
  for (let i = 0; ; i++) {
    try {
      std.writeFile(p, u8);
      return;
    } catch (e) {
      if (system.platform === "win32" && i < 30) {
        try {
          os.sleep(10);
        } catch (e2) {
        }
        continue;
      }
      throw e;
    }
  }
}

export function writeFile(filePath, data) {
  const u8 = toU8(data);
  let p = String(filePath);
  if (system.platform === "win32") {
    p = p.replace(/\//g, "\\");
    p = path.resolve(p);
    p = p.replace(/\//g, "\\");
  }
  try {
    mkdirp(path.dirname(p));
  } catch (e) {
  }
  for (let i = 0; ; i++) {
    try {
      std.writeFile(p, u8);
      return;
    } catch (e) {
      if (system.platform === "win32" && i < 30) {
        try {
          os.sleep(10);
        } catch (e2) {
        }
        continue;
      }
      throw e;
    }
  }
}

export function mkdir(path, mode) {
  const ret = os.mkdir(String(path), mode === void 0 ? 0o777 : mode);
  if (ret !== 0) throw new QjspError("QJSP_E_IO_MKDIR_FAILED", `mkdir: failed ${path} (errno=${ret})`, { path: String(path), errno: ret });
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
  if (err !== 0) throw new QjspError("QJSP_E_IO_READDIR_FAILED", `readdir: failed ${path} (errno=${err})`, { path: String(path), errno: err });
  return arr;
}

export function remove(path) {
  const ret = os.remove(String(path));
  if (ret !== 0) throw new QjspError("QJSP_E_IO_REMOVE_FAILED", `remove: failed ${path} (errno=${ret})`, { path: String(path), errno: ret });
}

export function rename(oldPath, newPath) {
  const ret = os.rename(String(oldPath), String(newPath));
  if (ret !== 0) throw new QjspError("QJSP_E_IO_RENAME_FAILED", `rename: failed (errno=${ret})`, { oldPath: String(oldPath), newPath: String(newPath), errno: ret });
}

function _statOrThrow(p) {
  const [st, err] = os.stat(String(p));
  if (err !== 0 || st == null) throw new QjspError("QJSP_E_IO_STAT_FAILED", `stat: failed ${p} (errno=${err})`, { path: String(p), errno: err });
  return st;
}

function _isDirStat(st) {
  return (st.mode & 0o170000) === 0o040000;
}

function _isFileStat(st) {
  return (st.mode & 0o170000) === 0o100000;
}

export function* walk(dir, opts) {
  const o = opts && typeof opts === "object" ? opts : {};
  const recursive = o.recursive !== void 0 ? !!o.recursive : true;
  const includeDirs = !!o.includeDirs;
  const filter = typeof o.filter === "function" ? o.filter : null;

  const root = String(dir);
  const rootSt = _statOrThrow(root);
  if (!_isDirStat(rootSt)) throw new QjspError("QJSP_E_IO_NOT_DIR", `walk: not a directory: ${root}`, { path: root });

  const stack = [root];
  while (stack.length) {
    const cur = stack.pop();
    const names = readdir(cur);
    for (const name of names) {
      if (name === "." || name === "..") continue;
      const full = path.join(cur, name);
      const st = stat(full);
      if (st == null) continue;

      const isDir = _isDirStat(st);
      const isFile = _isFileStat(st);

      if (filter && !filter(full, st)) {
        if (recursive && isDir) stack.push(full);
        continue;
      }

      if (isFile || (includeDirs && isDir)) yield full;
      if (recursive && isDir) stack.push(full);
    }
  }
}

export function walkArray(dir, opts) {
  return Array.from(walk(dir, opts));
}

export function* walkFiles(dir, opts) {
  yield* walk(dir, { ...(opts || {}), includeDirs: false });
}

export function* walkDirs(dir, opts) {
  yield* walk(dir, { ...(opts || {}), includeDirs: true, filter: (p, st) => _isDirStat(st) && (!(opts && typeof opts.filter === "function") || opts.filter(p, st)) });
}

export function copyFile(src, dst) {
  const s = String(src);
  const d = String(dst);
  const v = std.loadFile(s, { binary: true });
  if (v === null) throw new QjspError("QJSP_E_IO_READ_FAILED", `copyFile: cannot read ${s}`, { path: s });
  mkdirp(path.dirname(d));
  std.writeFile(d, toU8(v));
}

export function copyDir(srcDir, dstDir, opts) {
  const o = opts && typeof opts === "object" ? opts : {};
  const overwrite = !!o.overwrite;

  const srcRoot = String(srcDir);
  const dstRoot = String(dstDir);

  const srcSt = _statOrThrow(srcRoot);
  if (!_isDirStat(srcSt)) throw new QjspError("QJSP_E_IO_NOT_DIR", `copyDir: not a directory: ${srcRoot}`, { path: srcRoot });

  mkdirp(dstRoot);

  for (const p0 of walk(srcRoot, { recursive: true, includeDirs: true })) {
    const rel = path.normalize(String(p0)).slice(path.normalize(srcRoot).length).replace(/^[\\/]+/, "");
    const dstPath = rel ? path.join(dstRoot, rel) : dstRoot;
    const st = _statOrThrow(p0);
    if (_isDirStat(st)) {
      mkdirp(dstPath);
      continue;
    }
    if (!overwrite && exists(dstPath)) throw new QjspError("QJSP_E_IO_DEST_EXISTS", `copyDir: destination exists: ${dstPath}`, { path: dstPath });
    copyFile(p0, dstPath);
  }
}

export function removeTree(p) {
  const root = String(p);
  const st = stat(root);
  if (st == null) return;
  if (_isDirStat(st)) {
    for (const name of readdir(root)) {
      if (name === "." || name === "..") continue;
      removeTree(path.join(root, name));
    }
    remove(root);
    return;
  }
  remove(root);
}

export const rmrf = removeTree;

function _globSplit(s) {
  return String(s).replace(/\\/g, "/").split("/").filter((x) => x.length > 0);
}

function _globSegRe(seg) {
  const s = String(seg);
  let out = "^";
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (ch === "*") out += "[^/]*";
    else if (ch === "?") out += "[^/]";
    else out += ch.replace(/[\\^$.*+?()[\]{}|]/g, "\\$&");
  }
  out += "$";
  return new RegExp(out);
}

function _globMatchSegs(pathSegs, patSegs) {
  function rec(pi, si) {
    while (pi < patSegs.length) {
      const p = patSegs[pi];
      if (p === "**") {
        while (pi + 1 < patSegs.length && patSegs[pi + 1] === "**") pi++;
        if (pi + 1 >= patSegs.length) return true;
        for (let k = si; k <= pathSegs.length; k++) {
          if (rec(pi + 1, k)) return true;
        }
        return false;
      }
      if (si >= pathSegs.length) return false;
      const re = _globSegRe(p);
      if (!re.test(pathSegs[si])) return false;
      pi++;
      si++;
    }
    return si === pathSegs.length;
  }
  return rec(0, 0);
}

export function matchGlob(pattern, p) {
  const patSegs = _globSplit(pattern);
  const pathSegs = _globSplit(p);
  return _globMatchSegs(pathSegs, patSegs);
}

export function* globIter(pattern, opts) {
  const o = opts && typeof opts === "object" ? opts : {};
  const cwd = o.cwd !== void 0 ? String(o.cwd) : ".";
  const includeDirs = !!o.includeDirs;
  const patSegs = _globSplit(pattern);

  for (const full of walk(cwd, { recursive: true, includeDirs })) {
    const rel = path.normalize(String(full)).slice(path.normalize(cwd).length).replace(/^[\\/]+/, "");
    if (!rel) continue;
    const relSegs = _globSplit(rel);
    if (_globMatchSegs(relSegs, patSegs)) yield full;
  }
}

export function glob(pattern, opts) {
  return Array.from(globIter(pattern, opts));
}

export function tempDir() {
  return system.tmpdir();
}

function _mkdtempSuffix() {
  const n = Date.now().toString(16);
  const r = Math.floor(Math.random() * 0xffffffff).toString(16);
  return n + "-" + r;
}

export function mkdtemp(prefix, opts) {
  const o = opts && typeof opts === "object" ? opts : {};
  const pre = prefix !== void 0 ? String(prefix) : "tmp";

  const bases = [];
  if (o.dir !== void 0) {
    bases.push(String(o.dir));
  } else {
    bases.push(tempDir());
    bases.push(".");
    try {
      const hd = system.homedir();
      if (hd) bases.push(hd);
    } catch (e) {
    }
  }

  for (const base of bases) {
    try {
      mkdirp(base);
    } catch (e) {
      continue;
    }
    for (let i = 0; i < 100; i++) {
      const name = pre + "-" + _mkdtempSuffix();
      const p = path.join(base, name);
      try {
        mkdir(p);
        return p;
      } catch (e) {
      }
    }
  }

  throw new QjspError("QJSP_E_IO_MKDTEMP_FAILED", "mkdtemp: failed");
}

export async function withTempDir(fn, opts) {
  if (typeof fn !== "function") throw new TypeError("withTempDir: fn must be a function");
  const o = opts && typeof opts === "object" ? opts : {};
  const dir = mkdtemp(o.prefix !== void 0 ? o.prefix : "tmp", { dir: o.dir });
  try {
    return await fn(dir);
  } finally {
    try {
      rmrf(dir);
    } catch (e) {
    }
  }
}
const _watchCallbacks = new Map();
let _watchPumpAcquired = false;
let _watchShutdownHookInstalled = false;

function _shutdownAllWatches() {
  const ids = Array.from(_watchCallbacks.keys());
  for (const id of ids) {
    _watchCallbacks.delete(id);
    try {
      if (typeof globalThis.CloseWatch === "function") globalThis.CloseWatch(id);
    } catch (e) {
    }
  }
  if (globalThis.__qjspWatchCount !== void 0) {
    globalThis.__qjspWatchCount = 0;
  }
  try {
    releasePump("io:watch");
  } catch (e) {
  }
  _watchPumpAcquired = false;
}

function _ensureWatchPump() {
  if (_watchPumpAcquired) return;
  if (typeof globalThis.PumpWatchEvents !== "function") return;

  acquirePump("io:watch", () => {
    const events = globalThis.PumpWatchEvents();
    if (!events || events.length === 0) return;
    for (const ev of events) {
      const cb = _watchCallbacks.get(ev.id);
      if (!cb) continue;
      cb(ev);
    }
  }, 50);

  _watchPumpAcquired = true;

  if (!_watchShutdownHookInstalled && Array.isArray(globalThis.__qjspRuntimeShutdownCallbacks)) {
    globalThis.__qjspRuntimeShutdownCallbacks.push(_shutdownAllWatches);
    _watchShutdownHookInstalled = true;
  }
}

export function watch(dir, cb, opts) {
  if (typeof dir !== "string") dir = String(dir);
  if (typeof cb !== "function") throw new TypeError("watch: cb must be a function");
  const o = opts && typeof opts === "object" ? opts : {};
  const recursive = o.recursive !== void 0 ? !!o.recursive : true;

  dir = path.resolve(dir);
  if (system.platform === "win32") dir = dir.replace(/\//g, "\\");

  requireNative("watch", globalThis, "WatchDir");
  requireNative("watch", globalThis, "CloseWatch");

  const id = globalThis.WatchDir(dir, recursive);
  _watchCallbacks.set(id, cb);
  _ensureWatchPump();

  if (globalThis.__qjspWatchCount === void 0) globalThis.__qjspWatchCount = 0;
  globalThis.__qjspWatchCount = (globalThis.__qjspWatchCount | 0) + 1;

  return {
    id,
    close() {
      _watchCallbacks.delete(id);
      try {
        globalThis.CloseWatch(id);
      } catch (e) {
      }

      if (globalThis.__qjspWatchCount !== void 0) {
        globalThis.__qjspWatchCount = (globalThis.__qjspWatchCount | 0) - 1;
        if ((globalThis.__qjspWatchCount | 0) < 0) globalThis.__qjspWatchCount = 0;
      }

      if (_watchCallbacks.size === 0) {
        releasePump("io:watch");
        _watchPumpAcquired = false;
      }
    },
  };
}
