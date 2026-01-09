import * as fs from "qjsp:io/fs.js";
import { FileNotFoundException } from "qjsp:java/io/filenotfoundexception.js";
import { EOFException } from "qjsp:java/io/eofexception.js";

function _pathOf(p) {
  if (p && typeof p === "object" && typeof p.getPath === "function") return String(p.getPath());
  return String(p);
}

function _isWritableMode(m) {
  const s = String(m);
  return s.includes("w");
}

function _ensureCap(u8, want) {
  if (u8.length >= want) return u8;
  let cap = u8.length <= 0 ? 32 : u8.length;
  while (cap < want) cap *= 2;
  const nb = new Uint8Array(cap);
  nb.set(u8, 0);
  return nb;
}

export class RandomAccessFile {
  constructor(file, mode) {
    const path = _pathOf(file);
    const m = mode === void 0 ? "r" : String(mode);
    this._path = path;
    this._writable = _isWritableMode(m);
    this._closed = false;
    this._pos = 0;

    if (fs.exists(path)) {
      try {
        const data = fs.readFile(path);
        this._buf = new Uint8Array(data.length);
        this._buf.set(data);
        this._len = data.length;
      } catch (e) {
        throw new FileNotFoundException(String(e && e.message ? e.message : e));
      }
    } else {
      if (!this._writable) throw new FileNotFoundException("file not found");
      this._buf = new Uint8Array(0);
      this._len = 0;
    }
  }

  _checkOpen() {
    if (this._closed) throw new Error("RandomAccessFile is closed");
  }

  _checkWrite() {
    if (!this._writable) throw new Error("RandomAccessFile is read-only");
  }

  getFilePointer() {
    this._checkOpen();
    return this._pos;
  }

  length() {
    this._checkOpen();
    return this._len;
  }

  seek(pos) {
    this._checkOpen();
    const p = Number(pos);
    if (!Number.isFinite(p) || p < 0) throw new RangeError("RandomAccessFile.seek: pos must be >= 0");
    this._pos = p;
  }

  read() {
    this._checkOpen();
    if (this._pos >= this._len) return -1;
    return this._buf[this._pos++] & 0xff;
  }

  readBytes(b, off, len) {
    this._checkOpen();
    if (!(b instanceof Uint8Array)) throw new TypeError("RandomAccessFile.readBytes: b must be Uint8Array");
    const o = off === void 0 ? 0 : (Number(off) | 0);
    const l = len === void 0 ? (b.length - o) : (Number(len) | 0);
    if (o < 0 || l < 0 || o > b.length || o + l > b.length) throw new RangeError("RandomAccessFile.readBytes: invalid off/len");
    if (l === 0) return 0;
    const avail = this._len - this._pos;
    if (avail <= 0) return -1;
    const n = avail < l ? avail : l;
    b.set(this._buf.subarray(this._pos, this._pos + n), o);
    this._pos += n;
    return n;
  }

  readFully(b, off, len) {
    this._checkOpen();
    if (!(b instanceof Uint8Array)) throw new TypeError("RandomAccessFile.readFully: b must be Uint8Array");
    const o = off === void 0 ? 0 : (Number(off) | 0);
    const l = len === void 0 ? (b.length - o) : (Number(len) | 0);
    if (o < 0 || l < 0 || o > b.length || o + l > b.length) throw new RangeError("RandomAccessFile.readFully: invalid off/len");
    let got = 0;
    while (got < l) {
      const r = this.readBytes(b, o + got, l - got);
      if (r === -1) throw new EOFException("unexpected end of file");
      got += r;
    }
  }

  write(b) {
    this._checkOpen();
    this._checkWrite();
    const v = Number(b);
    if (!Number.isFinite(v)) throw new TypeError("RandomAccessFile.write: byte must be finite number");
    const need = this._pos + 1;
    this._buf = _ensureCap(this._buf, need);
    this._buf[this._pos++] = v & 0xff;
    if (need > this._len) this._len = need;
  }

  writeBytes(bytes, off, len) {
    this._checkOpen();
    this._checkWrite();
    if (!(bytes instanceof Uint8Array)) throw new TypeError("RandomAccessFile.writeBytes: bytes must be Uint8Array");
    const o = off === void 0 ? 0 : (Number(off) | 0);
    const l = len === void 0 ? (bytes.length - o) : (Number(len) | 0);
    if (o < 0 || l < 0 || o > bytes.length || o + l > bytes.length) throw new RangeError("RandomAccessFile.writeBytes: invalid off/len");
    if (l === 0) return;
    const need = this._pos + l;
    this._buf = _ensureCap(this._buf, need);
    this._buf.set(bytes.subarray(o, o + l), this._pos);
    this._pos += l;
    if (need > this._len) this._len = need;
  }

  setLength(newLength) {
    this._checkOpen();
    this._checkWrite();
    const n = Number(newLength);
    if (!Number.isFinite(n) || n < 0) throw new RangeError("RandomAccessFile.setLength: length must be >= 0");
    this._buf = _ensureCap(this._buf, n);
    if (n > this._len) this._buf.fill(0, this._len, n);
    this._len = n;
    if (this._pos > this._len) this._pos = this._len;
  }

  close() {
    if (this._closed) return;
    if (this._writable) {
      fs.writeFile(this._path, this._buf.slice(0, this._len));
    }
    this._closed = true;
  }
}

export default RandomAccessFile;
