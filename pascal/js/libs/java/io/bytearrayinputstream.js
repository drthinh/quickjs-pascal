import { InputStream } from "qjsp:java/io/inputstream.js";

function _toU8(buf) {
  if (buf instanceof Uint8Array) return buf;
  if (buf instanceof ArrayBuffer) return new Uint8Array(buf);
  if (ArrayBuffer.isView(buf)) return new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength);
  throw new TypeError("ByteArrayInputStream: expected Uint8Array/ArrayBuffer/view");
}

export class ByteArrayInputStream extends InputStream {
  constructor(buf, offset, length) {
    super();

    const u8 = _toU8(buf);
    const off = offset === void 0 ? 0 : (Number(offset) | 0);
    const len = length === void 0 ? (u8.length - off) : (Number(length) | 0);
    if (off < 0 || len < 0 || off > u8.length || off + len > u8.length) {
      throw new RangeError("ByteArrayInputStream: invalid offset/length");
    }

    this._buf = u8;
    this._start = off;
    this._pos = off;
    this._end = off + len;
    this._closed = false;
  }

  read() {
    if (this._closed) throw new Error("ByteArrayInputStream is closed");
    if (this._pos >= this._end) return -1;
    return this._buf[this._pos++] & 0xff;
  }

  readBytes(b, off, len) {
    if (this._closed) throw new Error("ByteArrayInputStream is closed");
    if (!(b instanceof Uint8Array)) throw new TypeError("ByteArrayInputStream.readBytes: b must be Uint8Array");

    const o = off === void 0 ? 0 : (Number(off) | 0);
    const l = len === void 0 ? (b.length - o) : (Number(len) | 0);
    if (o < 0 || l < 0 || o > b.length || o + l > b.length) throw new RangeError("ByteArrayInputStream.readBytes: invalid off/len");
    if (l === 0) return 0;

    const avail = this._end - this._pos;
    if (avail <= 0) return -1;

    const n = avail < l ? avail : l;
    b.set(this._buf.subarray(this._pos, this._pos + n), o);
    this._pos += n;
    return n;
  }

  skip(n) {
    if (this._closed) throw new Error("ByteArrayInputStream is closed");
    const nn = typeof n === "bigint" ? Number(n) : Number(n);
    if (!Number.isFinite(nn)) throw new TypeError("ByteArrayInputStream.skip(n): n must be finite");
    if (nn <= 0) return 0;

    const avail = this._end - this._pos;
    const k = nn > avail ? avail : nn;
    this._pos += k;
    return k;
  }

  available() {
    if (this._closed) return 0;
    return this._end - this._pos;
  }

  reset() {
    if (this._closed) throw new Error("ByteArrayInputStream is closed");
    this._pos = this._start;
  }

  close() {
    this._closed = true;
  }
}

export default ByteArrayInputStream;
