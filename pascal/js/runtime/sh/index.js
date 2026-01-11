import * as std from "qjs:std";
import * as os from "qjs:os";

import * as fs from "qjsp:io/fs.js";
import * as path from "qjsp:os/path.js";
import * as system from "qjsp:os/system.js";
import * as proc from "qjsp:os/process.js";
import * as env from "qjsp:os/env.js";
import { exec, execFile } from "qjsp:os/exec.js";
import { spawnp as _spawnp, spawn as _spawn } from "qjsp:os/spawn.js";

import { fetch as _fetch } from "qjsp:net/fetch.js";
import * as http from "qjsp:net/http.js";

import { runBuiltin } from "qjsp:sh/builtins.js";

export const platform = system.platform;

export const fetch = _fetch;

export async function download(url, outPath, opts) {
  const p = String(outPath);
  const r = await _fetch(String(url), opts);
  if (!r || typeof r.status !== "number") throw new Error("download: invalid response");
  if (r.status < 200 || r.status >= 300) throw new Error(`download: HTTP ${r.status}`);
  const ab = await r.arrayBuffer();
  fs.writeFile(p, new Uint8Array(ab));
  return p;
}

function _toStr(v) {
  return v == null ? "" : String(v);
}

function _quoteArgShell(s) {
  const v = String(s);
  if (v === "") return platform === "win32" ? '""' : "''";
  if (platform === "win32") {
    if (!/[\s"]/g.test(v)) return v;
    return '"' + v.replace(/"/g, '\\"') + '"';
  }
  if (!/[\s'"\\$`]/.test(v)) return v;
  return "'" + v.replace(/'/g, "'\\''") + "'";
}

function _splitLines(s) {
  const v = _toStr(s);
  if (v === "") return [];
  return v.replace(/\r\n/g, "\n").replace(/\r/g, "\n").split("\n");
}

function _trimFinalNewline(s) {
  const v = _toStr(s);
  return v.replace(/\r\n/g, "\n").replace(/\r/g, "\n").replace(/\n$/, "");
}

function _hasGlob(s) {
  const v = _toStr(s);
  return /[*?\[]/.test(v) || v.includes("**");
}

function _expandGlobs(args) {
  const out = [];
  for (const a of args) {
    const v = _toStr(a);
    if (!v || !_hasGlob(v)) {
      out.push(a);
      continue;
    }
    try {
      const matches = fs.glob(v.replace(/\\/g, "/"), { cwd: proc.cwd() });
      if (Array.isArray(matches) && matches.length) {
        for (const m of matches) out.push(m);
        continue;
      }
    } catch (e) {
    }
    out.push(a);
  }
  return out;
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

function _commandSubst(cmd) {
  const r = exec(_toStr(cmd));
  const out = r && typeof r.stdout === "string" ? r.stdout : "";
  return _trimFinalNewline(out);
}

function _expandCommandSubst(s) {
  const src = _toStr(s);
  if (!src) return src;

  let out = "";
  let inSingle = false;
  let inDouble = false;

  for (let i = 0; i < src.length; i++) {
    const ch = src[i];
    if (!inDouble && ch === "'") {
      inSingle = !inSingle;
      out += ch;
      continue;
    }
    if (!inSingle && ch === '"') {
      inDouble = !inDouble;
      out += ch;
      continue;
    }

    if (!inSingle && ch === "`") {
      const j = src.indexOf("`", i + 1);
      if (j < 0) {
        out += ch;
        continue;
      }
      const inner = src.slice(i + 1, j);
      out += _commandSubst(inner);
      i = j;
      continue;
    }

    if (!inSingle && ch === "$" && src[i + 1] === "(") {
      let depth = 0;
      let j = i + 1;
      for (; j < src.length; j++) {
        const c2 = src[j];
        if (c2 === "(") depth++;
        else if (c2 === ")") {
          depth--;
          if (depth === 0) break;
        } else if (c2 === "\\") {
          j++;
        }
      }
      if (depth !== 0 || j >= src.length) {
        out += ch;
        continue;
      }
      const inner = src.slice(i + 2, j);
      out += _commandSubst(inner);
      i = j;
      continue;
    }

    out += ch;
  }

  return out;
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

function _parseRedirections(line) {
  const s = _toStr(line);
  let cmd = "";
  let inSingle = false;
  let inDouble = false;

  let stdinFile = "";
  let stdoutFile = "";
  let append = false;

  let stderrFile = "";
  let stderrAppend = false;
  let stderrToStdout = false;
  let stdoutAndStderrFile = "";
  let stdoutAndStderrAppend = false;

  let hereString = "";

  const skipWs = (i) => {
    while (i < s.length && (s[i] === " " || s[i] === "\t")) i++;
    return i;
  };

  const readToken = (i) => {
    i = skipWs(i);
    if (i >= s.length) return { token: "", next: i };
    let t = "";
    let q1 = false;
    let q2 = false;
    while (i < s.length) {
      const ch = s[i];
      if (!q1 && !q2) {
        if (ch === " " || ch === "\t") break;
        if (ch === "'" || ch === '"') {
          if (ch === "'") q1 = true;
          else q2 = true;
          i++;
          continue;
        }
        if (ch === "\\") {
          i++;
          t += i < s.length ? s[i] : "\\";
          i++;
          continue;
        }
        t += ch;
        i++;
        continue;
      }

      if (q1) {
        if (ch === "'") {
          q1 = false;
          i++;
          continue;
        }
        t += ch;
        i++;
        continue;
      }

      if (q2) {
        if (ch === '"') {
          q2 = false;
          i++;
          continue;
        }
        if (ch === "\\") {
          i++;
          t += i < s.length ? s[i] : "\\";
          i++;
          continue;
        }
        t += ch;
        i++;
        continue;
      }
    }
    return { token: t, next: i };
  };

  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (!inSingle && !inDouble) {
      if (ch === "'") {
        inSingle = true;
        cmd += ch;
        continue;
      }
      if (ch === '"') {
        inDouble = true;
        cmd += ch;
        continue;
      }

      if (ch === "<" && s[i + 1] === "<" && s[i + 2] === "<") {
        const r = readToken(i + 3);
        hereString = _expandArg(r.token);
        i = r.next - 1;
        continue;
      }
      if (ch === "<") {
        const r = readToken(i + 1);
        stdinFile = r.token;
        i = r.next - 1;
        continue;
      }

      if (ch === "1" && s[i + 1] === ">") {
        let j = i + 2;
        let isAppend = false;
        if (j < s.length && s[j] === ">") {
          isAppend = true;
          j++;
        }
        const r = readToken(j);
        stdoutFile = r.token;
        append = isAppend;
        i = r.next - 1;
        continue;
      }

      if (ch === "2" && s[i + 1] === ">") {
        let j = i + 2;
        let isAppend = false;
        if (j < s.length && s[j] === ">") {
          isAppend = true;
          j++;
        }
        if (s.slice(j, j + 3) === "&1") {
          stderrToStdout = true;
          i = j + 2;
          continue;
        }
        const r = readToken(j);
        stderrFile = r.token;
        stderrAppend = isAppend;
        i = r.next - 1;
        continue;
      }

      if (ch === "&" && s[i + 1] === ">") {
        let j = i + 2;
        let isAppend = false;
        if (j < s.length && s[j] === ">") {
          isAppend = true;
          j++;
        }
        const r = readToken(j);
        stdoutAndStderrFile = r.token;
        stdoutAndStderrAppend = isAppend;
        i = r.next - 1;
        continue;
      }

      if (ch === ">") {
        let j = i + 1;
        let isAppend = false;
        if (j < s.length && s[j] === ">") {
          isAppend = true;
          j++;
        }
        const r = readToken(j);
        stdoutFile = r.token;
        append = isAppend;
        i = r.next - 1;
        continue;
      }
      cmd += ch;
      continue;
    }

    if (inSingle) {
      if (ch === "'") inSingle = false;
      cmd += ch;
      continue;
    }

    if (inDouble) {
      if (ch === '"') inDouble = false;
      if (ch === "\\") {
        cmd += ch;
        i++;
        if (i < s.length) cmd += s[i];
        continue;
      }
      cmd += ch;
      continue;
    }
  }

  return {
    cmd: cmd.trim(),
    stdinFile: stdinFile ? _expandArg(stdinFile) : "",
    stdoutFile: stdoutFile ? _expandArg(stdoutFile) : "",
    append,
    stderrFile: stderrFile ? _expandArg(stderrFile) : "",
    stderrAppend,
    stderrToStdout,
    stdoutAndStderrFile: stdoutAndStderrFile ? _expandArg(stdoutAndStderrFile) : "",
    stdoutAndStderrAppend,
    hereString: hereString ? _toStr(hereString) : "",
  };
}

function _writeRedirectText(filePath, text, append) {
  const p = _resolvePathExpanded(filePath);
  const s = _toStr(text);
  if (!append) {
    fs.writeTextFile(p, s);
    return;
  }
  try {
    if (typeof std.open === "function") {
      const f = std.open(p, "a");
      if (!f) throw new Error("open failed");
      f.puts(s);
      f.close();
      return;
    }
  } catch (e) {
  }
  const prev = fs.exists(p) ? fs.readTextFile(p) : "";
  fs.writeTextFile(p, prev + s);
}

function _makeTempFile(prefix, text) {
  const dir = fs.mkdtemp(prefix || "sh");
  const p = path.join(dir, "stdin.txt");
  fs.writeTextFile(p, _toStr(text));
  return { dir, path: p };
}

function _cleanupTemp(obj) {
  if (!obj || !obj.dir) return;
  try {
    fs.rmrf(obj.dir);
  } catch (e) {
  }
}

let _fgProc = null;

export function fg() {
  return _fgProc;
}

export function fgKill(sig) {
  if (_fgProc && typeof _fgProc.kill === "function") {
    try {
      _fgProc.kill(sig);
      return true;
    } catch (e) {
    }
  }
  return false;
}

function _runBuiltin(cmd, args, stdinText) {
  const api = {
    pwd,
    echo,
    ls,
    cat,
    head,
    tail,
    grep,
    find,
    which,
    platform,
    exec,
    execFile,
    toStr: _toStr,
    quoteArgShell: _quoteArgShell,
    trimFinalNewline: _trimFinalNewline,
    expandShortFlags: _expandShortFlags,
    isFlag: _isFlag,
    splitLines: _splitLines,
    expandArg: _expandArg,
    resolvePathExpanded: _resolvePathExpanded,
    buildSystemCommandWithInput: _buildSystemCommandWithInput,
    cleanupTemp: _cleanupTemp,
    warnCompat: _warnCompat,
    writeRedirectText: _writeRedirectText,
    formatTime: _formatTime,
    fs,
    path,
    proc,
    env,
    system,
    http,
  };
  return runBuiltin(cmd, args, stdinText, api);
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
  return _expandTilde(_expandVars(_expandCommandSubst(s)));
}

function _buildSystemCommandWithInput(rawCmd, stdinText) {
  if (stdinText == null) return _toStr(rawCmd);
  const tmp = _makeTempFile("sh-stdin", stdinText);
  const cmd = _toStr(rawCmd) + " < " + _quoteArgShell(tmp.path);
  return { cmd, tmp };
}

function _applySystemRedirects(cmd, redir) {
  let out = _toStr(cmd);
  if (redir.stdoutAndStderrFile) {
    const op = redir.stdoutAndStderrAppend ? ">>" : ">";
    out += ` ${op} ${_quoteArgShell(_resolvePathExpanded(redir.stdoutAndStderrFile))} 2>&1`;
    return out;
  }
  if (redir.stdoutFile) {
    const op = redir.append ? ">>" : ">";
    out += ` ${op} ${_quoteArgShell(_resolvePathExpanded(redir.stdoutFile))}`;
  }
  if (redir.stderrToStdout) {
    out += " 2>&1";
  } else if (redir.stderrFile) {
    const op2 = redir.stderrAppend ? ">>" : ">";
    out += ` 2${op2} ${_quoteArgShell(_resolvePathExpanded(redir.stderrFile))}`;
  }
  return out;
}

function _runPipeline(parts, redir) {
  let text = null;
  let tmpIn = null;
  if (redir.hereString) text = redir.hereString;
  if (redir.stdinFile) text = String(cat(redir.stdinFile));

  for (const part of parts) {
    let argv;
    try {
      argv = _splitArgsShell(part);
    } catch (e) {
      throw e;
    }
    argv = _expandGlobs(argv.map((a) => _expandArg(a)));
    if (!argv.length) continue;
    const cmd = String(argv[0]).toLowerCase();

    const b = _runBuiltin(cmd, argv, text);
    if (b != null) {
      text = String(b);
      continue;
    }

    const built = _buildSystemCommandWithInput(part, text);
    let sysCmd = typeof built === "string" ? built : built.cmd;
    tmpIn = typeof built === "string" ? null : built.tmp;
    sysCmd = _applySystemRedirects(sysCmd, redir);
    const r = exec(sysCmd);
    _cleanupTemp(tmpIn);
    tmpIn = null;
    text = r && typeof r.stdout === "string" ? _trimFinalNewline(r.stdout) : "";
  }

  return text;
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
  // Prefer spawn-based execution for streaming output (chunked).
  try {
    if (typeof _spawnp === "function") {
      const code = _spawnp(_toStr(command));
      return typeof code === "number" ? code : 0;
    }
  } catch (e) {
  }
  const r = run(command);
  if (r && typeof r.stdout === "string" && r.stdout !== "") _puts(r.stdout);
  const cmdPath = which(command);
  if (cmdPath) _puts(`[Native] ${command} - ${cmdPath}\n`);
  return r && typeof r.code === "number" ? r.code : 0;
}

export function repl(line) {
  const raw = _toStr(line).trim();
  if (!raw) return;

  if (_hasPipeOrRedirect(raw)) {
    const redir = _parseRedirections(raw);
    if (redir.cmd.includes("|")) {
      const parts = _splitPipeline(redir.cmd);
      if (parts) {
        let text;
        try {
          text = _runPipeline(parts, redir);
        } catch (e) {
          const msg = e && e.message ? e.message : String(e);
          const errText = "Error: " + msg + "\n";
          if (redir.stderrToStdout) {
            text = (text ? String(text) + "\n" : "") + errText;
          } else if (redir.stderrFile || redir.stdoutAndStderrFile) {
            const ef = redir.stdoutAndStderrFile || redir.stderrFile;
            const ea = redir.stdoutAndStderrFile ? redir.stdoutAndStderrAppend : redir.stderrAppend;
            _writeRedirectText(ef, errText, ea);
            return;
          } else {
            _puts(errText);
            return;
          }
        }
        if (text != null && text !== "") {
          const finalText = String(text) + "\n";
          if (redir.stdoutAndStderrFile) {
            _writeRedirectText(redir.stdoutAndStderrFile, finalText, redir.stdoutAndStderrAppend);
          } else if (redir.stdoutFile) {
            _writeRedirectText(redir.stdoutFile, finalText, redir.append);
          } else {
            _puts(finalText);
          }
        }
        return;
      }
    }

    if (redir.stdinFile || redir.stdoutFile || redir.stderrFile || redir.stderrToStdout || redir.stdoutAndStderrFile || redir.hereString) {
      let argv;
      try {
        argv = _splitArgsShell(redir.cmd);
      } catch (e) {
        _puts("Error: " + (e && e.message ? e.message : String(e)) + "\n");
        return;
      }
      if (!argv.length) return;
      argv = _expandGlobs(argv.map((a) => _expandArg(a)));
      const cmd = String(argv[0]).toLowerCase();
      let stdinText = null;
      if (redir.hereString) {
        stdinText = redir.hereString;
      } else if (redir.stdinFile) {
        try {
          stdinText = String(cat(redir.stdinFile));
        } catch (e) {
          _puts("Error: " + (e && e.message ? e.message : String(e)) + "\n");
          return;
        }
      }
      try {
        const out = _runBuiltin(cmd, argv, stdinText);
        if (out == null) {
          const built = _buildSystemCommandWithInput(redir.cmd, stdinText);
          let sysCmd = typeof built === "string" ? built : built.cmd;
          const tmp = typeof built === "string" ? null : built.tmp;
          sysCmd = _applySystemRedirects(sysCmd, redir);
          const rr = exec(sysCmd);
          _cleanupTemp(tmp);
          if (redir.stdoutFile || redir.stdoutAndStderrFile || redir.stderrFile) return;
          if (rr && typeof rr.stdout === "string" && rr.stdout !== "") _puts(rr.stdout);
          return;
        }
        const text = String(out);
        if (redir.stdoutAndStderrFile) {
          _writeRedirectText(redir.stdoutAndStderrFile, text === "" ? "" : (text + "\n"), redir.stdoutAndStderrAppend);
          return;
        }
        if (redir.stdoutFile) {
          _writeRedirectText(redir.stdoutFile, text === "" ? "" : (text + "\n"), redir.append);
          return;
        }
        if (text !== "") _puts(text + "\n");
        return;
      } catch (e) {
        const errText = "Error: " + (e && e.message ? e.message : String(e)) + "\n";
        if (redir.stderrToStdout) {
          _puts(errText);
        } else if (redir.stdoutAndStderrFile) {
          _writeRedirectText(redir.stdoutAndStderrFile, errText, redir.stdoutAndStderrAppend);
        } else if (redir.stderrFile) {
          _writeRedirectText(redir.stderrFile, errText, redir.stderrAppend);
        } else {
          _puts(errText);
        }
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
  args = _expandGlobs(args.map((a) => _expandArg(a)));
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

  if (cmd === "basename" || cmd === "dirname" || cmd === "realpath" || cmd === "stat" || cmd === "env" || cmd === "export" || cmd === "unset" || cmd === "sleep" || cmd === "date" || cmd === "clear" || cmd === "rmdir" || cmd === "mktemp" || cmd === "wc" || cmd === "sort" || cmd === "uniq" || cmd === "cut" || cmd === "tr" || cmd === "tee" || cmd === "xargs" || cmd === "ps" || cmd === "kill" || cmd === "ln") {
    try {
      const out = _runBuiltin(cmd, args, null);
      if (out != null && String(out) !== "") _puts(String(out) + "\n");
    } catch (e) {
      _puts("Error: " + (e && e.message ? e.message : String(e)) + "\n");
    }
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

  if (cmd === "sed") {
    try {
      const out = _runBuiltin("sed", args, null);
      if (out != null && String(out) !== "") _puts(String(out) + "\n");
    } catch (e) {
      _puts("Error: " + (e && e.message ? e.message : String(e)) + "\n");
    }
    return;
  }

  if (cmd === "awk") {
    try {
      const out = _runBuiltin("awk", args, null);
      if (out != null && String(out) !== "") _puts(String(out) + "\n");
    } catch (e) {
      _puts("Error: " + (e && e.message ? e.message : String(e)) + "\n");
    }
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
  // IMPORTANT: do not block the Pascal REPL by returning a Promise that will be awaited.
  // Run as foreground process with streaming output via spawn.
  try {
    const p = which(args[0]);
    if (p != null && String(p) !== "") {
      _puts(`[Native] ${_toStr(args[0])} - ${String(p)}\n`);
    }
  } catch (e) {
  }
  try {
    if (typeof _spawn === "function") {
      const argv = platform === "win32" ? ["cmd.exe", "/C", raw] : ["sh", "-c", raw];
      _fgProc = _spawn(argv, { mergeStderr: true, inheritStdio: true, shell: true });
      try {
        _fgProc.waitSync();
      } finally {
        _fgProc = null;
      }
      if (platform === "win32") {
        os.sleep(100);
      }
      _puts("\n");
      return;
    }
    _puts("Error: spawn unavailable (sh module not updated?)\n");
    return;
  } catch (e) {
    const msg = e && e.message ? e.message : String(e);
    _puts("Error: spawn failed: " + msg + "\n");
    return;
  }
  runp(raw);
}

export function runFile(file, args, opts) {
  return execFile(_toStr(file), args, opts);
}

export function help() {
  _puts("sh mode\n");
  _puts("=======\n\n");
  _puts("Built-in commands:\n");
  _puts("  pwd\n");
  _puts("  cd <dir>\n");
  _puts("  ls [-a] [-l] [path]\n");
  _puts("  which <cmd>\n");
  _puts("  mkdir [-p] <dir>\n");
  _puts("  rm [-r] [-f] [-i] <path>\n");
  _puts("  cat <file>\n");
  _puts("  head <file> [n]\n");
  _puts("  tail <file> [n]\n");
  _puts("  cp [-r|-a] [-f] <src> <dst>\n");
  _puts("  mv <src> <dst>\n");
  _puts("  touch <file>\n");
  _puts("  grep [-r] [-i] [-n] <pattern> <path>\n");
  _puts("  find [start] [-name GLOB] [-type f|d] [-maxdepth N]\n");
  _puts("  run <command>\n\n");
  _puts("Other:\n");
  _puts("  .js   Return to JS prompt\n");
  _puts("  help  Show this help\n\n");
}
