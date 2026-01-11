import { OutputStream } from "qjsp:java/io/outputstream.js";

function _isOutputStreamLike(v) {
  return v != null &&
    typeof v.write === "function" &&
    typeof v.writeBytes === "function" &&
    typeof v.flush === "function" &&
    typeof v.close === "function";
}

export class BufferedOutputStream extends OutputStream {
  constructor(output, size) {
    super();
    if (!_isOutputStreamLike(output)) throw new TypeError("BufferedOutputStream(output[, size]): output must be OutputStream");
    const n = size === void 0 ? 8192 : (Number(size) | 0);
    if (n <= 0) throw new RangeError("BufferedOutputStream: size must be > 0");
    this._out = output;
    this._buf = new Uint8Array(n);
    this._count = 0;
    this._closed = false;
  }

  _flushBuf() {
    if (this._count <= 0) return;
    this._out.writeBytes(this._buf, 0, this._count);
    this._count = 0;
  }

  write(b) {
    if (this._closed) throw new Error("BufferedOutputStream is closed");
    if (this._count >= this._buf.length) this._flushBuf();
    this._buf[this._count++] = Number(b) & 0xff;
  }

  writeBytes(bytes, off, len) {
    if (this._closed) throw new Error("BufferedOutputStream is closed");
    if (!(bytes instanceof Uint8Array)) throw new TypeError("BufferedOutputStream.writeBytes: bytes must be Uint8Array");
    const o = off === void 0 ? 0 : (Number(off) | 0);
    const l = len === void 0 ? (bytes.length - o) : (Number(len) | 0);
    if (o < 0 || l < 0 || o > bytes.length || o + l > bytes.length) throw new RangeError("BufferedOutputStream.writeBytes: invalid off/len");
    if (l === 0) return;

    if (l >= this._buf.length) {
      this._flushBuf();
      this._out.writeBytes(bytes, o, l);
      return;
    }

    if (this._count + l > this._buf.length) this._flushBuf();
    this._buf.set(bytes.subarray(o, o + l), this._count);
    this._count += l;
  }

  flush() {
    if (this._closed) return;
    this._flushBuf();
    this._out.flush();
  }

  close() {
    if (this._closed) return;
    this.flush();
    this._closed = true;
    this._out.close();
  }
}

export default BufferedOutputStream;
