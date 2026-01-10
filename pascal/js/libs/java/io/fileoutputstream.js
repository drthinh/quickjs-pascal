import * as fs from "qjsp:io/fs.js";
import { OutputStream } from "qjsp:java/io/outputstream.js";

function _pathOf(p) {
  if (p && typeof p === "object" && typeof p.getPath === "function") return String(p.getPath());
  return String(p);
}

function _concatU8(parts) {
  let total = 0;
  for (const p of parts) total += p.length;
  const out = new Uint8Array(total);
  let off = 0;
  for (const p of parts) {
    out.set(p, off);
    off += p.length;
  }
  return out;
}

export class FileOutputStream extends OutputStream {
  constructor(file, append) {
    super();
    this._path = _pathOf(file);
    this._append = !!append;
    this._chunks = [];
    this._size = 0;
    this._closed = false;
  }

  write(b) {
    if (this._closed) throw new Error("FileOutputStream is closed");
    const v = Number(b);
    if (!Number.isFinite(v)) throw new TypeError("FileOutputStream.write: byte must be finite number");
    this._chunks.push(new Uint8Array([v & 0xff]));
    this._size += 1;
  }

  writeBytes(bytes, off, len) {
    if (this._closed) throw new Error("FileOutputStream is closed");
    if (!(bytes instanceof Uint8Array)) throw new TypeError("FileOutputStream.writeBytes: bytes must be Uint8Array");
    const o = off === void 0 ? 0 : (Number(off) | 0);
    const l = len === void 0 ? (bytes.length - o) : (Number(len) | 0);
    if (o < 0 || l < 0 || o > bytes.length || o + l > bytes.length) throw new RangeError("FileOutputStream.writeBytes: invalid off/len");
    if (l === 0) return;
    const slice = bytes.subarray(o, o + l);
    const copy = new Uint8Array(slice.length);
    copy.set(slice);
    this._chunks.push(copy);
    this._size += copy.length;
  }

  flush() {
    if (this._closed) return;
    if (this._size === 0) {
      if (!this._append) {
        fs.writeFile(this._path, new Uint8Array(0));
      }
      return;
    }

    let data = _concatU8(this._chunks);
    if (this._append && fs.exists(this._path)) {
      const prev = fs.readFile(this._path);
      data = _concatU8([prev, data]);
    }

    fs.writeFile(this._path, data);
    this._chunks = [];
    this._size = 0;
    this._append = true;
  }

  close() {
    if (this._closed) return;
    this.flush();
    this._closed = true;
  }
}

export default FileOutputStream;
