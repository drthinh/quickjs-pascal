export class InputStream {
  constructor() {}

  read() {
    throw new Error("java.io.InputStream.read is not implemented");
  }

  readBytes(b, off, len) {
    if (!(b instanceof Uint8Array)) throw new TypeError("InputStream.readBytes(b[, off[, len]]): b must be Uint8Array");

    const o = off === void 0 ? 0 : (Number(off) | 0);
    const l = len === void 0 ? (b.length - o) : (Number(len) | 0);
    if (o < 0 || l < 0 || o > b.length || o + l > b.length) throw new RangeError("InputStream.readBytes: invalid off/len");

    if (l === 0) return 0;

    let i = 0;
    for (; i < l; i++) {
      const v = this.read();
      if (v === -1) break;
      b[o + i] = v & 0xff;
    }

    return i === 0 ? -1 : i;
  }

  skip(n) {
    const nn = typeof n === "bigint" ? Number(n) : Number(n);
    if (!Number.isFinite(nn)) throw new TypeError("InputStream.skip(n): n must be finite");
    if (nn <= 0) return 0;

    const buf = new Uint8Array(1024);
    let remaining = nn;
    while (remaining > 0) {
      const want = remaining > buf.length ? buf.length : remaining;
      const r = this.readBytes(buf, 0, want);
      if (r === -1) break;
      remaining -= r;
    }
    return nn - remaining;
  }

  available() {
    return 0;
  }

  close() {}

  markSupported() {
    return false;
  }

  mark(readlimit) {}

  reset() {
    throw new Error("java.io.InputStream.reset is not supported");
  }
}

export default InputStream;
