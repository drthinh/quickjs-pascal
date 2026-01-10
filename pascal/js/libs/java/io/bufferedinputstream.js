import { InputStream } from "qjsp:java/io/inputstream.js";

export class BufferedInputStream extends InputStream {
  constructor(input, size) {
    super();
    if (!(input instanceof InputStream)) throw new TypeError("BufferedInputStream(input[, size]): input must be InputStream");
    const n = size === void 0 ? 8192 : (Number(size) | 0);
    if (n <= 0) throw new RangeError("BufferedInputStream: size must be > 0");
    this._in = input;
    this._buf = new Uint8Array(n);
    this._pos = 0;
    this._len = 0;
    this._closed = false;
  }

  _fill() {
    this._pos = 0;
    const r = this._in.readBytes(this._buf, 0, this._buf.length);
    this._len = r === -1 ? 0 : r;
    return this._len;
  }

  read() {
    if (this._closed) throw new Error("BufferedInputStream is closed");
    if (this._pos >= this._len) {
      if (this._fill() === 0) return -1;
    }
    return this._buf[this._pos++] & 0xff;
  }

  readBytes(b, off, len) {
    if (this._closed) throw new Error("BufferedInputStream is closed");
    if (!(b instanceof Uint8Array)) throw new TypeError("BufferedInputStream.readBytes: b must be Uint8Array");

    const o = off === void 0 ? 0 : (Number(off) | 0);
    const l = len === void 0 ? (b.length - o) : (Number(len) | 0);
    if (o < 0 || l < 0 || o > b.length || o + l > b.length) throw new RangeError("BufferedInputStream.readBytes: invalid off/len");
    if (l === 0) return 0;

    let done = 0;
    while (done < l) {
      if (this._pos >= this._len) {
        if (this._fill() === 0) break;
      }
      const avail = this._len - this._pos;
      const take = (l - done) < avail ? (l - done) : avail;
      b.set(this._buf.subarray(this._pos, this._pos + take), o + done);
      this._pos += take;
      done += take;
    }

    return done === 0 ? -1 : done;
  }

  available() {
    if (this._closed) return 0;
    return (this._len - this._pos) + (typeof this._in.available === "function" ? this._in.available() : 0);
  }

  close() {
    if (this._closed) return;
    this._closed = true;
    this._in.close();
  }
}

export default BufferedInputStream;
