import * as fs from "qjsp:io/fs.js";
import * as p from "qjsp:io/path.js";
import { Path } from "qjsp:java/nio/file/path.js";

export class File {
  constructor(path) {
    if (path instanceof File) this._path = path._path;
    else this._path = p.normalize(String(path));
  }

  getPath() { return this._path; }
  toString() { return this._path; }
  exists() { return fs.exists(this._path); }
  isDirectory() { return fs.isDirectory(this._path); }
  isFile() { return fs.isFile(this._path); }
  length() { return fs.isFile(this._path) ? fs.stat(this._path).size : 0; }
  delete() { if (!fs.exists(this._path)) return false; fs.remove(this._path); return true; }
  mkdirs() { fs.mkdirp(this._path); return true; }
  getName() { return p.basename(this._path); }
  getParent() { const d = p.dirname(this._path); if (d === "." || d === this._path) return null; return d; }
  toPath() {
    // java.nio.file.Path facade
    return new Path(this._path);
  }

  static separatorChar() { return p.sep; }
}

export default File;
