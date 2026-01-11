import * as fs from "qjsp:io/fs.js";
import { Path } from "qjsp:java/nio/file/path.js";

function _p(pth) {
  return pth instanceof Path ? pth.toString() : String(pth);
}

export const StandardOpenOption = Object.freeze({
  // Placeholder for future expansion.
  CREATE: "CREATE",
  TRUNCATE_EXISTING: "TRUNCATE_EXISTING",
  APPEND: "APPEND",
});

export const Files = Object.freeze({
  exists(path) {
    return fs.exists(_p(path));
  },

  walk(path, opts) {
    const p0 = _p(path);
    const o = opts && typeof opts === "object" ? opts : {};
    const recursive = o.recursive !== void 0 ? !!o.recursive : true;
    const includeDirs = !!o.includeDirs;
    return fs.walk(p0, { recursive, includeDirs });
  },

  walkArray(path, opts) {
    return Array.from(Files.walk(path, opts));
  },

  glob(pattern, opts) {
    const o = opts && typeof opts === "object" ? opts : {};
    return fs.glob(String(pattern), o);
  },

  createTempDirectory(prefix, opts) {
    const o = opts && typeof opts === "object" ? opts : {};
    const dir = fs.mkdtemp(prefix === void 0 ? "tmp" : String(prefix), { dir: o.dir });
    return new Path(dir);
  },

  watch(path, listener, opts) {
    return fs.watch(_p(path), listener, opts);
  },

  readAllBytes(path) {
    return fs.readFile(_p(path));
  },

  readString(path, charset) {
    if (charset !== void 0 && charset !== null && String(charset).toLowerCase() !== "utf-8") {
      throw new Error("Files.readString: only utf-8 is supported");
    }
    return fs.readTextFile(_p(path));
  },

  write(path, bytes, options) {
    // Minimal: overwrite/create.
    // options currently ignored (kept for signature compatibility).
    fs.writeFile(_p(path), bytes);
    return path instanceof Path ? path : new Path(_p(path));
  },

  writeString(path, text, charset, options) {
    if (charset !== void 0 && charset !== null && String(charset).toLowerCase() !== "utf-8") {
      throw new Error("Files.writeString: only utf-8 is supported");
    }
    // options currently ignored.
    fs.writeTextFile(_p(path), text);
    return path instanceof Path ? path : new Path(_p(path));
  },

  createDirectories(path) {
    fs.mkdirp(_p(path));
    return path instanceof Path ? path : new Path(_p(path));
  },

  deleteIfExists(path) {
    const p0 = _p(path);
    if (!fs.exists(p0)) return false;
    fs.remove(p0);
    return true;
  },
});
