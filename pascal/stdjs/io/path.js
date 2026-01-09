function _isAbsPosix(p) {
  return p.length > 0 && p[0] === "/";
}

function _isAbsWin(p) {
  return /^[A-Za-z]:[\\/]/.test(p) || /^\\\\/.test(p);
}

export function isAbsolute(p) {
  p = String(p);
  return _isAbsPosix(p) || _isAbsWin(p);
}

export function normalize(p) {
  p = String(p);
  const sep = p.indexOf("\\") >= 0 ? "\\" : "/";
  const parts = p.split(/[\\/]+/);
  const out = [];
  const abs = isAbsolute(p);

  for (const part of parts) {
    if (!part || part === ".") continue;
    if (part === "..") {
      if (out.length && out[out.length - 1] !== "..") out.pop();
      else if (!abs) out.push("..");
      continue;
    }
    out.push(part);
  }

  let res = out.join(sep);
  if (abs) {
    if (_isAbsWin(p) && /^[A-Za-z]:/.test(p)) {
      const drive = p.slice(0, 2);
      res = drive + sep + res;
    } else if (/^\\\\/.test(p)) {
      res = "\\\\" + res;
    } else {
      res = "/" + res;
    }
  }

  return res === "" ? (abs ? (sep === "\\" && /^[A-Za-z]:/.test(p) ? p.slice(0, 2) + sep : sep) : ".") : res;
}

export function join(...parts) {
  if (parts.length === 0) return "";
  const strs = parts.map((x) => String(x)).filter((x) => x.length > 0);
  if (strs.length === 0) return "";
  const sep = strs.some((s) => s.indexOf("\\") >= 0) ? "\\" : "/";
  return normalize(strs.join(sep));
}

export function dirname(p) {
  p = normalize(String(p));
  const sep = p.indexOf("\\") >= 0 ? "\\" : "/";
  const idx = p.lastIndexOf(sep);
  if (idx < 0) return ".";
  if (idx === 0) return sep;
  return p.slice(0, idx);
}

export function basename(p) {
  p = normalize(String(p));
  const sep = p.indexOf("\\") >= 0 ? "\\" : "/";
  const idx = p.lastIndexOf(sep);
  return idx < 0 ? p : p.slice(idx + 1);
}

export function extname(p) {
  const b = basename(p);
  const i = b.lastIndexOf(".");
  if (i <= 0) return "";
  return b.slice(i);
}

export function resolve(...parts) {
  const strs = parts.map((x) => String(x)).filter((x) => x.length > 0);
  if (strs.length === 0) return "";

  let acc = "";
  for (let i = strs.length - 1; i >= 0; i--) {
    const s = strs[i];
    acc = acc ? join(s, acc) : s;
    if (isAbsolute(s)) break;
  }
  return normalize(acc);
}
