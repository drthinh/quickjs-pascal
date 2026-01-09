import * as std from "qjs:std";
import * as os from "qjs:os";

import * as fs from "qjsp:io/fs.js";
import * as path from "qjsp:os/path.js";
import * as system from "qjsp:os/system.js";
import * as proc from "qjsp:os/process.js";
import * as env from "qjsp:os/env.js";
import { exec, execFile } from "qjsp:os/exec.js";

export const platform = system.platform;

function _toStr(v) {
  return v == null ? "" : String(v);
}

function _splitLines(s) {
  const v = _toStr(s);
  if (v === "") return [];
  return v.replace(/\r\n/g, "\n").replace(/\r/g, "\n").split("\n");
}

function _isDir(p) {
  const st = fs.stat(p);
  if (!st) return false;
  return (st.mode & 0o170000) === 0o040000;
}

function _isFile(p) {
  const st = fs.stat(p);
  if (!st) return false;
  return (st.mode & 0o170000) === 0o100000;
}

function _warnCompat(msg) {
  if (typeof std.err !== "undefined" && std.err && typeof std.err.puts === "function") {
    try {
      std.err.puts(String(msg) + "\n");
    } catch (e) {
    }
  }
}

function _puts(s) {
  if (typeof std.out !== "undefined" && std.out && typeof std.out.puts === "function") {
    try {
      std.out.puts(String(s));
      return;
    } catch (e) {
    }
  }
  try {
    std.print(String(s));
  } catch (e) {
  }
}

function _formatColumns(items, width) {
  const out = Array.isArray(items) ? items.map(_toStr) : [];
  if (out.length === 0) return "";

  let maxLen = 0;
  for (const s of out) maxLen = Math.max(maxLen, s.length);

  const colWidth = Math.min(Math.max(4, maxLen + 2), Math.max(4, width));
  const cols = Math.max(1, Math.floor(width / colWidth));
  const rows = Math.ceil(out.length / cols);

  const pad = (s) => {
    const v = _toStr(s);
    if (v.length >= colWidth) return v;
    return v + " ".repeat(colWidth - v.length);
  };

  const lines = [];
  for (let r = 0; r < rows; r++) {
    let line = "";
    for (let c = 0; c < cols; c++) {
      const idx = c * rows + r;
      if (idx >= out.length) continue;
      const s = out[idx];
      line += c === cols - 1 ? _toStr(s) : pad(s);
    }
    lines.push(line.replace(/\s+$/g, ""));
  }
  return lines.join("\n");
}

function _formatTime(st) {
  try {
    const t = st && st.mtime != null ? Number(st.mtime) : NaN;
    if (!Number.isFinite(t)) return "";
    return new Date(t * 1000).toISOString().replace("T", " ").slice(0, 19);
  } catch (e) {
    return "";
  }
}

function _padLeft(s, n) {
  const v = _toStr(s);
  if (v.length >= n) return v;
  return " ".repeat(n - v.length) + v;
}

function _splitArgsShell(line) {
  const s = _toStr(line);
  const out = [];
  let cur = "";
  let inSingle = false;
  let inDouble = false;

  const push = () => {
    if (cur !== "") out.push(cur);
    cur = "";
  };

  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (!inSingle && !inDouble) {
      if (ch === " " || ch === "\t") {
        push();
        continue;
      }
      if (ch === "'") {
        inSingle = true;
        continue;
      }
      if (ch === '"') {
        inDouble = true;
        continue;
      }
      if (ch === "\\") {
        i++;
        cur += i < s.length ? s[i] : "\\";
        continue;
      }
      cur += ch;
      continue;
    }

    if (inSingle) {
      if (ch === "'") {
        inSingle = false;
        continue;
      }
      cur += ch;
      continue;
    }

    if (inDouble) {
      if (ch === '"') {
        inDouble = false;
        continue;
      }
      if (ch === "\\") {
        i++;
        cur += i < s.length ? s[i] : "\\";
        continue;
      }
      cur += ch;
      continue;
    }
  }

  if (inSingle || inDouble) throw new Error("unterminated quote");
  push();
  return out;
}

function _hasPipeOrRedirect(line) {
  const s = _toStr(line);
  return s.includes("|") || s.includes(">") || s.includes("<");
}

function _splitPipeline(line) {
  const s = _toStr(line);
  const parts = [];
  let cur = "";
  let inSingle = false;
  let inDouble = false;

  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (!inSingle && !inDouble) {
      if (ch === "'") {
        inSingle = true;
        cur += ch;
        continue;
      }
      if (ch === '"') {
        inDouble = true;
        cur += ch;
        continue;
      }
      if (ch === "|") {
        parts.push(cur.trim());
        cur = "";
        continue;
      }
      cur += ch;
      continue;
    }

    if (inSingle) {
      if (ch === "'") inSingle = false;
      cur += ch;
      continue;
    }

    if (inDouble) {
      if (ch === '"') inDouble = false;
      if (ch === "\\") {
        cur += ch;
        i++;
        if (i < s.length) cur += s[i];
        continue;
      }
      cur += ch;
      continue;
    }
  }

  if (inSingle || inDouble) return null;
  if (cur.trim() !== "") parts.push(cur.trim());
  if (parts.length <= 1) return null;
  return parts;
}

function _runBuiltin(cmd, args, stdinText) {
  const a0 = args.length >= 2 ? args[1] : "";

  if (cmd === "pwd") return pwd();
  if (cmd === "echo") return echo(...args.slice(1));

  if (cmd === "ls") {
    let all = false;
    let target = "";
    for (let i = 1; i < args.length; i++) {
      const rawA = String(args[i]);
      const expanded = _expandShortFlags(rawA);
      const list = expanded ? expanded : [rawA];
      for (const a of list) {
        if (a === "-a" || a === "--all") all = true;
        else if (_isFlag(a)) {
        } else if (!target) {
          target = _expandArg(a);
        }
      }
    }
    if (!target) target = ".";
    const items = ls(target, all ? { all: true } : void 0);
    return Array.isArray(items) ? items.join("\n") : _toStr(items);
  }

  if (cmd === "cat") {
    if (!a0) throw new Error("Usage: cat <file>");
    return String(cat(_expandArg(a0)));
  }

  if (cmd === "grep") {
    let recursive = false;
    let ignoreCase = false;
    let lineNumber = false;
    const pos = [];
    for (let i = 1; i < args.length; i++) {
      const rawA = String(args[i]);
      const expanded = _expandShortFlags(rawA);
      const list = expanded ? expanded : [rawA];
      for (const a of list) {
        if (a === "-r" || a === "-R" || a === "--recursive") recursive = true;
        else if (a === "-i" || a === "--ignore-case") ignoreCase = true;
        else if (a === "-n" || a === "--line-number") lineNumber = true;
        else if (_isFlag(a)) {
        } else pos.push(a);
      }
    }

    if (stdinText != null && pos.length >= 1) {
      const pat = pos[0] instanceof RegExp ? pos[0] : new RegExp(_toStr(pos[0]), ignoreCase ? "i" : "");
      const lines = _splitLines(stdinText);
      const out = [];
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (pat.test(line)) out.push(lineNumber ? `${i + 1}:${line}` : line);
      }
      return out.join("\n");
    }

    if (pos.length < 2) throw new Error("Usage: grep [-r] [-i] [-n] <pattern> <path>");
    return String(grep(pos[0], _expandArg(pos[1]), { ...(recursive ? { recursive: true } : {}), ...(ignoreCase ? { ignoreCase: true } : {}), ...(lineNumber ? { lineNumber: true } : {}) }));
  }

  if (cmd === "find") {
    const haveStdin = stdinText != null;
    const hasFsFlags = args.some((x) => x === "-name" || x === "-type" || x === "-maxdepth");

    if (haveStdin && !hasFsFlags) {
      if (!a0) throw new Error("Usage: find <text>");
      const needle = _toStr(a0);
      const lines = _splitLines(stdinText);
      const out = [];
      for (const line of lines) {
        if (line.includes(needle)) out.push(line);
      }
      return out.join("\n");
    }

    let start = ".";
    let name = "";
    let type = "";
    let maxDepth = void 0;

    const pos = [];
    for (let i = 1; i < args.length; i++) pos.push(String(args[i]));

    let i = 0;
    if (pos.length && !_isFlag(pos[0])) {
      start = _expandArg(pos[0]);
      i = 1;
    }

    for (; i < pos.length; i++) {
      const a = pos[i];
      if (a === "-name") {
        i++;
        name = i < pos.length ? String(pos[i]) : "";
      } else if (a === "-type") {
        i++;
        type = i < pos.length ? String(pos[i]) : "";
      } else if (a === "-maxdepth") {
        i++;
        maxDepth = i < pos.length ? Number(pos[i]) : void 0;
      }
    }

    const res = find(start, { ...(name ? { name } : {}), ...(type ? { type } : {}), ...(maxDepth != null ? { maxDepth } : {}) });
    return Array.isArray(res) ? res.join("\n") : _toStr(res);
  }

  if (cmd === "which") {
    if (!a0) throw new Error("Usage: which <cmd>");
    const r = which(_expandArg(a0));
    return r == null ? "" : String(r);
  }

  return null;
}

function _isFlag(s) {
  const v = _toStr(s);
  return v.startsWith("-") && v.length > 1;
}

function _expandShortFlags(arg) {
  const a = _toStr(arg);
  if (!a.startsWith("-") || a.startsWith("--") || a === "-") return null;
  const flags = [];
  for (let i = 1; i < a.length; i++) {
    flags.push("-" + a[i]);
  }
  return flags;
}

function _homeDir() {
  try {
    const hd = system.homedir();
    if (hd) return String(hd);
  } catch (e) {
  }
  const e1 = env.get(platform === "win32" ? "USERPROFILE" : "HOME", "");
  if (e1) return String(e1);
  const e2 = env.get("HOME", "");
  if (e2) return String(e2);
  return "";
}

function _expandVars(s) {
  const v = _toStr(s);
  if (!v) return v;
  return v
    .replace(/\$\{([A-Za-z_][A-Za-z0-9_]*)\}/g, (m, name) => {
      const val = env.get(String(name), "");
      return val == null ? "" : String(val);
    })
    .replace(/\$([A-Za-z_][A-Za-z0-9_]*)/g, (m, name) => {
      const val = env.get(String(name), "");
      return val == null ? "" : String(val);
    });
}

function _expandTilde(s) {
  const v = _toStr(s);
  if (!v) return v;
  if (!v.startsWith("~")) return v;
  const home = _homeDir();
  if (!home) return v;
  if (v === "~") return home;
  if (v.startsWith("~/") || v.startsWith("~\\")) return path.join(home, v.slice(2));
  return v;
}

function _expandArg(s) {
  return _expandTilde(_expandVars(s));
}

function _readLine(prompt) {
  if (prompt) _puts(String(prompt));
  try {
    if (std && std.in && typeof std.in.getline === "function") {
      const line = std.in.getline();
      if (line == null) return null;
      return String(line).replace(/\r?\n$/, "");
    }
  } catch (e) {
  }
  return null;
}

function _resolvePath(p) {
  let s = _toStr(p);
  if (!s) return s;
  if (platform === "win32") s = s.replace(/\//g, "\\");
  if (!path.isAbsolute(s)) s = path.resolve(proc.cwd(), s);
  else s = path.resolve(s);
  if (platform === "win32") s = s.replace(/\//g, "\\");
  return s;
}

function _resolvePathExpanded(p) {
  return _resolvePath(_expandArg(p));
}

export function pwd() {
  return proc.cwd();
}

export function cd(p) {
  proc.chdir(_toStr(p));
}

export function echo(...args) {
  return args.map(_toStr).join(" ");
}

export function ls(p, opts) {
  const o = opts && typeof opts === "object" ? opts : {};
  const target = _resolvePathExpanded(p === void 0 ? "." : p);
  const names = fs.readdir(target);
  let out = names.filter((n) => n !== "." && n !== "..");
  if (!o.all) out = out.filter((n) => !n.startsWith("."));
  out.sort((a, b) => a.localeCompare(b));
  if (o.fullPath) return out.map((n) => path.join(target, n));
  return out;
}

export function lsLong(p, opts) {
  const o = opts && typeof opts === "object" ? opts : {};
  const target = _resolvePathExpanded(p === void 0 ? "." : p);
  const names = fs.readdir(target);
  let out = names.filter((n) => n !== "." && n !== "..");
  if (!o.all) out = out.filter((n) => !n.startsWith("."));
  out.sort((a, b) => a.localeCompare(b));

  const rows = [];
  for (const name of out) {
    const full = path.join(target, name);
    const st = fs.stat(full);
    const isDir = !!st && ((st.mode & 0o170000) === 0o040000);
    rows.push({
      name,
      fullPath: full,
      type: isDir ? "d" : "-",
      size: st && typeof st.size === "number" ? st.size : 0,
      mtime: _formatTime(st),
    });
  }
  return rows;
}

export function lsLongPretty(p, opts) {
  const rows = lsLong(p, opts);
  if (!rows.length) return;
  let sizeW = 0;
  for (const r of rows) sizeW = Math.max(sizeW, String(r.size).length);
  for (const r of rows) {
    _puts(`${r.type} ${_padLeft(r.size, sizeW)} ${r.mtime} ${r.name}\n`);
  }
}

export function lsPretty(p, opts) {
  const o = opts && typeof opts === "object" ? opts : {};
  const items = ls(p, o);
  const width = Math.max(40, Math.min(200, Math.floor(Number(o.width || 80))));
  const text = _formatColumns(items, width);
  if (text !== "") _puts(text + "\n");
}

export function mkdir(p, opts) {
  const o = opts && typeof opts === "object" ? opts : {};
  const target = _resolvePathExpanded(p);
  if (o.p || o.parents) {
    fs.mkdirp(target);
    return;
  }
  fs.mkdir(target);
}

export function rm(p, opts) {
  const o = opts && typeof opts === "object" ? opts : {};
  const target = _resolvePathExpanded(p);

  if (o.interactive || o.i) {
    if (o.force || o.f) {
    } else {
      const ans = _readLine(`rm: remove '${target}'? [y/N] `);
      if (ans == null) throw new Error("rm: interactive prompt not available");
      const ok = /^y(es)?$/i.test(String(ans).trim());
      if (!ok) return;
    }
  }

  if (o.recursive || o.r || o.rf || o.rmrf) {
    try {
      fs.rmrf(target);
    } catch (e) {
      if (!o.force && !o.f) throw e;
    }
    return;
  }
  try {
    fs.remove(target);
  } catch (e) {
    if (!o.force && !o.f) throw e;
  }
}

export function mv(src, dst) {
  fs.rename(_resolvePathExpanded(src), _resolvePathExpanded(dst));
}

export function cp(src, dst, opts) {
  const o = opts && typeof opts === "object" ? opts : {};
  const s = _resolvePathExpanded(src);
  const d = _resolvePathExpanded(dst);

  const recursive = !!(o.recursive || o.r || o.R || o.a || o.archive);
  const overwrite = !!(o.overwrite || o.f || o.force);
  const preserve = !!(o.preserve || o.p || o.a || o.archive);

  if (_isDir(s)) {
    if (!recursive) throw new Error(`cp: omitting directory '${s}' (use -r)`);
    fs.copyDir(s, d, { overwrite });
    if (preserve) {
      try {
        const st = fs.stat(s);
        if (st && platform !== "win32" && typeof os.utimes === "function") {
          os.utimes(d, st.atime, st.mtime);
        }
        if (st && typeof os.chmod === "function") {
          os.chmod(d, st.mode & 0o777);
        }
      } catch (e) {
      }
    }
    return;
  }

  if (!overwrite && fs.exists(d)) throw new Error(`cp: destination exists: ${d}`);
  fs.copyFile(s, d);
  if (preserve) {
    try {
      const st = fs.stat(s);
      if (st && platform !== "win32" && typeof os.utimes === "function") {
        os.utimes(d, st.atime, st.mtime);
      }
      if (st && typeof os.chmod === "function") {
        os.chmod(d, st.mode & 0o777);
      }
    } catch (e) {
    }
  }
}

export function touch(filePath) {
  const p = _resolvePathExpanded(filePath);
  if (!fs.exists(p)) {
    fs.writeTextFile(p, "");
    return;
  }

  if (platform !== "win32") {
    try {
      if (typeof os.utimes === "function") {
        const now = Date.now() / 1000;
        os.utimes(p, now, now);
      }
    } catch (e) {
    }
    return;
  }

  _warnCompat("touch: mtime update not supported on win32 in this build; file left unchanged");
}

export function cat(filePath) {
  const p = _resolvePathExpanded(filePath);
  if (!fs.exists(p) || !_isFile(p)) {
    throw new Error(`cat: file not found: ${p} (cwd=${pwd()})`);
  }
  return fs.readTextFile(p);
}

export function head(filePath, n) {
  const count = n === void 0 ? 10 : Math.max(0, Math.floor(Number(n)));
  const lines = _splitLines(cat(filePath));
  return lines.slice(0, count).join("\n");
}

export function tail(filePath, n) {
  const count = n === void 0 ? 10 : Math.max(0, Math.floor(Number(n)));
  const lines = _splitLines(cat(filePath));
  return lines.slice(Math.max(0, lines.length - count)).join("\n");
}

export function grep(pattern, filePath, opts) {
  const o = opts && typeof opts === "object" ? opts : {};

  const target = _resolvePathExpanded(filePath);
  const pat = pattern instanceof RegExp ? pattern : new RegExp(_toStr(pattern), o.ignoreCase ? "i" : "");

  const out = [];
  const visitFile = (p) => {
    const text = fs.readTextFile(p);
    const lines = _splitLines(text);
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (pat.test(line)) {
        if (o.recursive || o.r) {
          if (o.lineNumber) out.push(`${p}:${i + 1}:${line}`);
          else out.push(`${p}:${line}`);
        } else {
          if (o.lineNumber) out.push(`${i + 1}:${line}`);
          else out.push(line);
        }
      }
    }
  };

  if (_isDir(target) && (o.recursive || o.r)) {
    for (const p of fs.walkFiles(target, { recursive: true })) {
      try {
        visitFile(p);
      } catch (e) {
      }
    }
  } else {
    visitFile(target);
  }

  return o.count ? out.length : out.join("\n");
}

function _findWalk(root, opts) {
  const o = opts && typeof opts === "object" ? opts : {};
  const maxDepth = o.maxDepth != null ? Math.max(0, Math.floor(Number(o.maxDepth))) : Infinity;
  const includeDirs = o.includeDirs !== void 0 ? !!o.includeDirs : true;
  const includeFiles = o.includeFiles !== void 0 ? !!o.includeFiles : true;
  const type = o.type ? String(o.type) : "";
  const name = o.name != null ? String(o.name) : "";

  const stack = [{ dir: root, depth: 0 }];
  const out = [];
  while (stack.length) {
    const cur = stack.pop();
    const names = fs.readdir(cur.dir);
    for (const entry of names) {
      if (entry === "." || entry === "..") continue;
      const full = path.join(cur.dir, entry);
      const st = fs.stat(full);
      if (!st) continue;
      const isDir = (st.mode & 0o170000) === 0o040000;
      const isFile = (st.mode & 0o170000) === 0o100000;

      if (cur.depth < maxDepth && isDir) {
        stack.push({ dir: full, depth: cur.depth + 1 });
      }

      if (type === "f" && !isFile) continue;
      if (type === "d" && !isDir) continue;
      if (!includeDirs && isDir) continue;
      if (!includeFiles && isFile) continue;
      if (name && !fs.matchGlob(name, entry)) continue;

      out.push(full);
    }
  }
  return out;
}

export function find(start, opts) {
  const o = opts && typeof opts === "object" ? opts : {};
  const root = _resolvePathExpanded(start === void 0 ? "." : start);
  if (!fs.exists(root)) throw new Error(`find: path not found: ${root}`);
  const st = fs.stat(root);
  if (!st) return [];
  const isDir = (st.mode & 0o170000) === 0o040000;
  if (!isDir) return [root];
  return _findWalk(root, o);
}

export function which(cmd, opts) {
  const o = opts && typeof opts === "object" ? opts : {};
  const name = _toStr(cmd);
  if (!name) return null;

  const hasSep = /[\\/]/.test(name);
  if (hasSep) {
    const p = path.resolve(_expandArg(name));
    if (fs.exists(p) && _isFile(p)) return p;
    return null;
  }

  const pathVar = env.get(platform === "win32" ? "PATH" : "PATH", "") || "";
  const dirs = String(pathVar).split(platform === "win32" ? ";" : ":").filter((x) => x);

  const exts = platform === "win32" ? (env.get("PATHEXT", ".EXE;.CMD;.BAT;.COM") || ".EXE;.CMD;.BAT;.COM").split(";") : [""];

  for (const dir of dirs) {
    for (const ext of exts) {
      const cand = path.join(dir, platform === "win32" ? (name.endsWith(ext) ? name : name + ext) : name);
      if (fs.exists(cand) && _isFile(cand)) return o.all ? [cand] : cand;
    }
  }

  return o.all ? [] : null;
}

export function run(command) {
  return exec(_toStr(command));
}

export function runp(command) {
  const r = run(command);
  if (r && typeof r.stdout === "string" && r.stdout !== "") _puts(r.stdout);
  return r && typeof r.code === "number" ? r.code : 0;
}

export function repl(line) {
  const raw = _toStr(line).trim();
  if (!raw) return;

  if (_hasPipeOrRedirect(raw)) {
    if (raw.includes("|") && !raw.includes(">") && !raw.includes("<")) {
      const parts = _splitPipeline(raw);
      if (parts) {
        let text = null;
        for (const part of parts) {
          let argv;
          try {
            argv = _splitArgsShell(part);
          } catch (e) {
            _puts("Error: " + (e && e.message ? e.message : String(e)) + "\n");
            return;
          }
          if (!argv.length) continue;
          const cmd = String(argv[0]).toLowerCase();
          try {
            const out = _runBuiltin(cmd, argv, text);
            if (out == null) {
              _puts("Error: pipeline supports builtins only\n");
              return;
            }
            text = String(out);
          } catch (e) {
            _puts("Error: " + (e && e.message ? e.message : String(e)) + "\n");
            return;
          }
        }
        if (text != null && text !== "") _puts(text + "\n");
        return;
      }
    }

    runp(raw);
    return;
  }

  let args;
  try {
    args = _splitArgsShell(raw);
  } catch (e) {
    _puts("Error: " + (e && e.message ? e.message : String(e)) + "\n");
    return;
  }
  if (!args.length) return;

  const cmd = String(args[0]).toLowerCase();
  const a0 = args.length >= 2 ? args[1] : "";

  if (cmd === "pwd") {
    _puts(pwd() + "\n");
    return;
  }

  if (cmd === "cd") {
    if (!a0) {
      _puts("Usage: cd <dir>\n");
      return;
    }
    cd(_expandArg(a0));
    return;
  }

  if (cmd === "ls") {
    let all = false;
    let long = false;
    let target = "";
    for (let i = 1; i < args.length; i++) {
      const rawA = String(args[i]);
      const expanded = _expandShortFlags(rawA);
      const list = expanded ? expanded : [rawA];
      for (const a of list) {
        if (a === "-a" || a === "--all") all = true;
        else if (a === "-l" || a === "--long") long = true;
        else if (_isFlag(a)) {
          _puts("Warning: unknown ls option: " + a + "\n");
        } else if (!target) {
          target = _expandArg(a);
        }
      }
    }
    if (!target) target = ".";
    const opts = all ? { all: true } : void 0;
    if (long) lsLongPretty(target, opts);
    else lsPretty(target, opts);
    return;
  }

  if (cmd === "which") {
    if (!a0) {
      _puts("Usage: which <cmd>\n");
      return;
    }
    const r = which(_expandArg(a0));
    if (r != null) _puts(String(r) + "\n");
    return;
  }

  if (cmd === "mkdir") {
    let parents = false;
    let target = "";
    for (let i = 1; i < args.length; i++) {
      const rawA = String(args[i]);
      const expanded = _expandShortFlags(rawA);
      const list = expanded ? expanded : [rawA];
      for (const a of list) {
        if (a === "-p" || a === "--parents") parents = true;
        else if (_isFlag(a)) {
          _puts("Warning: unknown mkdir option: " + a + "\n");
        } else if (!target) {
          target = a;
        }
      }
    }
    if (!target) {
      _puts("Usage: mkdir [-p] <dir>\n");
      return;
    }
    mkdir(target, parents ? { p: true } : void 0);
    return;
  }

  if (cmd === "rm") {
    let recursive = false;
    let force = false;
    let interactive = false;
    let target = "";
    for (let i = 1; i < args.length; i++) {
      const rawA = String(args[i]);
      const expanded = _expandShortFlags(rawA);
      const list = expanded ? expanded : [rawA];
      for (const a of list) {
        if (a === "-r" || a === "-R" || a === "--recursive") recursive = true;
        else if (a === "-f" || a === "--force") force = true;
        else if (a === "-i" || a === "--interactive") interactive = true;
        else if (_isFlag(a)) {
          _puts("Warning: unknown rm option: " + a + "\n");
        } else if (!target) {
          target = _expandArg(a);
        }
      }
    }
    if (!target) {
      _puts("Usage: rm [-r] [-f] [-i] <path>\n");
      return;
    }
    const opts = recursive || force || interactive ? { ...(recursive ? { recursive: true } : {}), ...(force ? { force: true } : {}), ...(interactive ? { interactive: true } : {}) } : void 0;
    rm(target, opts);
    return;
  }

  if (cmd === "cat") {
    if (!a0) {
      _puts("Usage: cat <file>\n");
      return;
    }
    _puts(String(cat(_expandArg(a0))) + "\n");
    return;
  }

  if (cmd === "head") {
    if (!a0) {
      _puts("Usage: head <file> [n]\n");
      return;
    }
    const n = args.length >= 3 ? Number(args[2]) : void 0;
    _puts(String(head(_expandArg(a0), n)) + "\n");
    return;
  }

  if (cmd === "tail") {
    if (!a0) {
      _puts("Usage: tail <file> [n]\n");
      return;
    }
    const n = args.length >= 3 ? Number(args[2]) : void 0;
    _puts(String(tail(_expandArg(a0), n)) + "\n");
    return;
  }

  if (cmd === "cp") {
    let recursive = false;
    let archive = false;
    let force = false;
    const pos = [];
    for (let i = 1; i < args.length; i++) {
      const rawA = String(args[i]);
      const expanded = _expandShortFlags(rawA);
      const list = expanded ? expanded : [rawA];
      for (const a of list) {
        if (a === "-r" || a === "-R" || a === "--recursive") recursive = true;
        else if (a === "-a" || a === "--archive") archive = true;
        else if (a === "-f" || a === "--force") force = true;
        else if (_isFlag(a)) _puts("Warning: unknown cp option: " + a + "\n");
        else pos.push(_expandArg(a));
      }
    }
    if (pos.length < 2) {
      _puts("Usage: cp [-r|-a] [-f] <src> <dst>\n");
      return;
    }
    cp(pos[0], pos[1], { ...(recursive ? { recursive: true } : {}), ...(archive ? { archive: true } : {}), ...(force ? { force: true } : {}) });
    return;
  }

  if (cmd === "mv") {
    if (args.length < 3) {
      _puts("Usage: mv <src> <dst>\n");
      return;
    }
    mv(_expandArg(args[1]), _expandArg(args[2]));
    return;
  }

  if (cmd === "touch") {
    if (!a0) {
      _puts("Usage: touch <file>\n");
      return;
    }
    touch(_expandArg(a0));
    return;
  }

  if (cmd === "echo") {
    _puts(echo(...args.slice(1)) + "\n");
    return;
  }

  if (cmd === "grep") {
    let recursive = false;
    let ignoreCase = false;
    let lineNumber = false;
    const pos = [];
    for (let i = 1; i < args.length; i++) {
      const rawA = String(args[i]);
      const expanded = _expandShortFlags(rawA);
      const list = expanded ? expanded : [rawA];
      for (const a of list) {
        if (a === "-r" || a === "-R" || a === "--recursive") recursive = true;
        else if (a === "-i" || a === "--ignore-case") ignoreCase = true;
        else if (a === "-n" || a === "--line-number") lineNumber = true;
        else if (_isFlag(a)) _puts("Warning: unknown grep option: " + a + "\n");
        else pos.push(a);
      }
    }
    if (pos.length < 2) {
      _puts("Usage: grep [-r] [-i] [-n] <pattern> <path>\n");
      return;
    }
    _puts(String(grep(pos[0], _expandArg(pos[1]), { ...(recursive ? { recursive: true } : {}), ...(ignoreCase ? { ignoreCase: true } : {}), ...(lineNumber ? { lineNumber: true } : {}) })) + "\n");
    return;
  }

  if (cmd === "find") {
    let start = ".";
    let name = "";
    let type = "";
    let maxDepth = void 0;

    const pos = [];
    for (let i = 1; i < args.length; i++) pos.push(String(args[i]));

    let i = 0;
    if (pos.length && !_isFlag(pos[0])) {
      start = _expandArg(pos[0]);
      i = 1;
    }

    for (; i < pos.length; i++) {
      const a = pos[i];
      if (a === "-name") {
        i++;
        name = i < pos.length ? String(pos[i]) : "";
      } else if (a === "-type") {
        i++;
        type = i < pos.length ? String(pos[i]) : "";
      } else if (a === "-maxdepth") {
        i++;
        maxDepth = i < pos.length ? Number(pos[i]) : void 0;
      } else if (_isFlag(a)) {
        _puts("Warning: unknown find option: " + a + "\n");
      }
    }

    const res = find(start, { ...(name ? { name } : {}), ...(type ? { type } : {}), ...(maxDepth != null ? { maxDepth } : {}) });
    if (Array.isArray(res) && res.length) _puts(res.join("\n") + "\n");
    return;
  }

  if (cmd === "run") {
    if (!a0) {
      _puts("Usage: run <command>\n");
      return;
    }
    runp(a0);
    return;
  }

  // fallback to system command
  runp(raw);
}

export function runFile(file, args, opts) {
  return execFile(_toStr(file), args, opts);
}
