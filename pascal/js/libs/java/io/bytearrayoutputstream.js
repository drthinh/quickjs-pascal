import { OutputStream } from "qjsp:java/io/outputstream.js";

function _nextCap(cur, want) {
  let c = cur <= 0 ? 32 : cur;
  while (c < want) c = c * 2;
  return c;
}

export class ByteArrayOutputStream extends OutputStream {
  constructor(size) {
    super();
    const n = size === void 0 ? 32 : (Number(size) | 0);
    if (n < 0) throw new RangeError("ByteArrayOutputStream(size): size must be >= 0");
    this._buf = new Uint8Array(n);
    this._count = 0;
    this._closed = false;
  }

  _ensure(extra) {
    const want = this._count + extra;
    if (want <= this._buf.length) return;
    const nb = new Uint8Array(_nextCap(this._buf.length, want));
    nb.set(this._buf.subarray(0, this._count), 0);
    this._buf = nb;
  }

  write(b) {
    if (this._closed) throw new Error("ByteArrayOutputStream is closed");
    const v = Number(b);
    if (!Number.isFinite(v)) throw new TypeError("ByteArrayOutputStream.write: byte must be finite number");
    this._ensure(1);
    this._buf[this._count++] = v & 0xff;
  }

  writeBytes(bytes, off, len) {
    if (this._closed) throw new Error("ByteArrayOutputStream is closed");
    if (!(bytes instanceof Uint8Array)) throw new TypeError("ByteArrayOutputStream.writeBytes: bytes must be Uint8Array");
    const o = off === void 0 ? 0 : (Number(off) | 0);
    const l = len === void 0 ? (bytes.length - o) : (Number(len) | 0);
    if (o < 0 || l < 0 || o > bytes.length || o + l > bytes.length) throw new RangeError("ByteArrayOutputStream.writeBytes: invalid off/len");
    if (l === 0) return;
    this._ensure(l);
    this._buf.set(bytes.subarray(o, o + l), this._count);
    this._count += l;
  }

  size() {
    return this._count;
  }

  toByteArray() {
    return this._buf.slice(0, this._count);
  }

  reset() {
    if (this._closed) throw new Error("ByteArrayOutputStream is closed");
    this._count = 0;
  }

  close() {
    this._closed = true;
  }
}

export default ByteArrayOutputStream;
