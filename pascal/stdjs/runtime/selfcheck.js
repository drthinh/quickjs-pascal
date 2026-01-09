import * as std from "qjs:std";
import * as os from "qjs:os";

function _readText(p) {
  const v = std.loadFile(String(p), { binary: false });
  return v == null ? null : String(v);
}

function _isDir(st) {
  if (!st) return false;
  return (st.mode & 0o170000) === 0o040000;
}

function _isFile(st) {
  if (!st) return false;
  return (st.mode & 0o170000) === 0o100000;
}

function _join(a, b) {
  const aa = String(a).replace(/\\/g, "/").replace(/\/+$/g, "");
  const bb = String(b).replace(/\\/g, "/").replace(/^\/+/, "");
  return aa ? (aa + "/" + bb) : bb;
}

function _walk(root, rel, out) {
  const p = rel ? _join(root, rel) : String(root);
  const [arr, err] = os.readdir(p);
  if (err !== 0 || !Array.isArray(arr)) return;
  for (const name of arr) {
    if (name === "." || name === "..") continue;
    const childRel = rel ? _join(rel, name) : String(name);
    const child = _join(root, childRel);
    const [st, stErr] = os.stat(child);
    if (stErr !== 0) continue;
    if (_isDir(st)) {
      _walk(root, childRel, out);
    } else if (_isFile(st)) {
      out.push(childRel);
    }
  }
}

function _detectCaseCollisions(files) {
  const map = new Map();
  const collisions = [];
  for (const f of files) {
    const k = String(f).toLowerCase();
    const prev = map.get(k);
    if (prev && prev !== f) {
      collisions.push([prev, f]);
    } else {
      map.set(k, f);
    }
  }
  return collisions;
}

function _detectSelfImport(root, relPath) {
  const text = _readText(_join(root, relPath));
  if (text == null) return null;
  const relNoExt = String(relPath).replace(/\\/g, "/").replace(/\.js$/i, "");
  // best-effort: detect exact self import of this file
  const patterns = [
    `\"qjsp:${relNoExt}.js\"`,
    `\'qjsp:${relNoExt}.js\'`,
    `\"qjsp:${relNoExt}\"`,
    `\'qjsp:${relNoExt}\'`,
  ];
  for (const s of patterns) {
    if (text.indexOf(s) >= 0) return s;
  }
  return null;
}

export function selfCheckStdjs(opts) {
  const o = opts && typeof opts === "object" ? opts : {};
  const root = o.root ? String(o.root) : "stdjs";
  const checkCaseCollision = o.checkCaseCollision !== false;
  const checkSelfImport = o.checkSelfImport !== false;

  const files = [];
  _walk(root, "", files);

  if (checkCaseCollision) {
    const collisions = _detectCaseCollisions(files);
    if (collisions.length) {
      const lines = collisions.map((p) => `  - ${p[0]}  <->  ${p[1]}`).join("\n");
      throw new Error("runtime:selfcheck: case-collision detected under " + root + " (Windows will break imports):\n" + lines);
    }
  }

  if (checkSelfImport) {
    for (const f of files) {
      if (!/\.js$/i.test(f)) continue;
      const hit = _detectSelfImport(root, f);
      if (hit) {
        throw new Error("runtime:selfcheck: self-import detected in " + f + " via " + hit);
      }
    }
  }

  return { ok: true, fileCount: files.length };
}
