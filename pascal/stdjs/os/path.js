function splitPath(p) {
  const s = String(p);
  return s.split(/[\\/]+/);
}

export const sep = "\\";

export function split(p) {
  return splitPath(p).filter((x) => x.length > 0);
}

export function isUNC(p) {
  const s = String(p);
  return s.startsWith("\\\\") && !s.startsWith("\\\\?\\");
}

export function toPosix(p) {
  return String(p).replace(/\\/g, "/");
}

export function toWin(p) {
  return String(p).replace(/\//g, "\\");
}

export function isAbsolute(p) {
  const s = String(p);
  return s.startsWith("/") || s.startsWith("\\") || /^[A-Za-z]:[\\/]/.test(s) || s.startsWith("\\\\");
}

export function normalize(p) {
  const s = String(p);
  const parts = splitPath(s);

  let prefix = "";
  let i = 0;

  if (/^[A-Za-z]:$/.test(parts[0])) {
    prefix = parts[0] + "\\";
    i = 1;
  } else if (s.startsWith("\\\\")) {
    prefix = "\\\\";
  } else if (s.startsWith("/")) {
    prefix = "/";
  }

  const out = [];
  for (; i < parts.length; i++) {
    const part = parts[i];
    if (!part || part === ".") continue;
    if (part === "..") {
      if (out.length > 0 && out[out.length - 1] !== "..") out.pop();
      else if (!prefix) out.push("..");
      continue;
    }
    out.push(part);
  }

  const joined = out.join("\\");
  return prefix ? (prefix.endsWith("\\") || prefix.endsWith("/") ? prefix + joined : prefix + "\\" + joined) : joined;
}

export function join(...parts) {
  let s = "";
  for (const part of parts) {
    const v = String(part);
    if (!v) continue;
    if (!s) s = v;
    else s = s.replace(/[\\/]+$/, "") + "\\" + v.replace(/^[\\/]+/, "");
  }
  return normalize(s);
}

export function dirname(p) {
  const s = normalize(p);
  const i = Math.max(s.lastIndexOf("\\"), s.lastIndexOf("/"));
  if (i < 0) return ".";
  if (i === 0) return s[0];
  return s.slice(0, i);
}

export function basename(p, ext) {
  const s = String(p);
  const i = Math.max(s.lastIndexOf("\\"), s.lastIndexOf("/"));
  let b = i >= 0 ? s.slice(i + 1) : s;
  if (ext && b.endsWith(String(ext))) b = b.slice(0, b.length - String(ext).length);
  return b;
}

export function extname(p) {
  const b = basename(p);
  const i = b.lastIndexOf(".");
  if (i <= 0) return "";
  return b.slice(i);
}

export function resolve(...parts) {
  let out = "";
  for (const part of parts) {
    const v = String(part);
    if (!v) continue;
    if (isAbsolute(v)) out = v;
    else out = out ? join(out, v) : v;
  }
  return normalize(out);
}

export function parse(p) {
  const s0 = String(p);
  const s = normalize(s0);

  let root = "";
  let rest = s;

  const mDrive = /^[A-Za-z]:\\/.exec(s);
  if (mDrive) {
    root = s.slice(0, 3);
    rest = s.slice(3);
  } else if (s.startsWith("\\\\")) {
    root = "\\\\";
    rest = s.slice(2);
  } else if (s.startsWith("/")) {
    root = "/";
    rest = s.slice(1);
  }

  const lastSep = Math.max(rest.lastIndexOf("\\"), rest.lastIndexOf("/"));
  const dirRest = lastSep >= 0 ? rest.slice(0, lastSep) : "";
  const base = lastSep >= 0 ? rest.slice(lastSep + 1) : rest;
  const dir = root ? (dirRest ? root + dirRest : root) : (dirRest ? dirRest : "");

  const dot = base.lastIndexOf(".");
  const ext = dot > 0 ? base.slice(dot) : "";
  const name = dot > 0 ? base.slice(0, dot) : base;

  return { root, dir, base, ext, name };
}

export function format(obj) {
  const o = obj && typeof obj === "object" ? obj : {};
  const dir = o.dir != null ? String(o.dir) : "";
  const root = o.root != null ? String(o.root) : "";
  const base = o.base != null ? String(o.base) : "";
  const name = o.name != null ? String(o.name) : "";
  const ext = o.ext != null ? String(o.ext) : "";

  const b = base || (name + ext);
  if (!dir) {
    if (root) return normalize(join(root, b));
    return normalize(b);
  }
  return normalize(join(dir, b));
}

export function relative(from, to) {
  const f = resolve(from);
  const t = resolve(to);

  const fp = splitPath(f).filter((x) => x.length > 0);
  const tp = splitPath(t).filter((x) => x.length > 0);

  const isWinDrive = (x) => /^[A-Za-z]:$/.test(x);
  const sameSeg = (a, b) => {
    if (isWinDrive(a) && isWinDrive(b)) return a.toLowerCase() === b.toLowerCase();
    return a === b;
  };

  let i = 0;
  for (; i < fp.length && i < tp.length; i++) {
    if (!sameSeg(fp[i], tp[i])) break;
  }

  const up = fp.slice(i).map(() => "..");
  const down = tp.slice(i);
  const parts = up.concat(down);
  return parts.length ? parts.join("\\") : "";
}
