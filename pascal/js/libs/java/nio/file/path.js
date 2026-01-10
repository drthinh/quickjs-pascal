import * as p from "qjsp:io/path.js";

export class Path {
  constructor(pathString) {
    this._path = p.normalize(String(pathString));
  }

  static of(...parts) {
    if (parts.length === 0) throw new TypeError("Path.of: at least one part is required");
    return new Path(p.join(...parts.map((x) => String(x))));
  }

  toString() {
    return this._path;
  }

  toAbsolutePath() {
    return new Path(p.resolve(this._path));
  }

  getFileName() {
    return p.basename(this._path);
  }

  getParent() {
    const d = p.dirname(this._path);
    if (d === "." || d === this._path) return null;
    return new Path(d);
  }

  resolve(other) {
    const s = other instanceof Path ? other.toString() : String(other);
    return new Path(p.join(this._path, s));
  }

  normalize() {
    return new Path(p.normalize(this._path));
  }

  isAbsolute() {
    return p.isAbsolute(this._path);
  }
}
