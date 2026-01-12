const _kReader = Symbol.for("qjsp.java.io.Reader");

export class Reader {
  static [Symbol.hasInstance](instance) {
    return !!(instance && instance[_kReader]);
  }

  constructor() {
    this[_kReader] = true;
  }

  read() {
    throw new Error("java.io.Reader.read is not implemented");
  }

  readChars(cbuf, off, len) {
    if (!Array.isArray(cbuf) && !(cbuf instanceof Uint16Array)) {
      throw new TypeError("Reader.readChars(cbuf[, off[, len]]): cbuf must be Array or Uint16Array");
    }
    const o = off === void 0 ? 0 : (Number(off) | 0);
    const l = len === void 0 ? (cbuf.length - o) : (Number(len) | 0);
    if (o < 0 || l < 0 || o > cbuf.length || o + l > cbuf.length) throw new RangeError("Reader.readChars: invalid off/len");
    if (l === 0) return 0;

    let i = 0;
    for (; i < l; i++) {
      const v = this.read();
      if (v === -1) break;
      if (cbuf instanceof Uint16Array) cbuf[o + i] = v & 0xffff;
      else cbuf[o + i] = String.fromCharCode(v & 0xffff);
    }

    return i === 0 ? -1 : i;
  }

  close() {}
}

export default Reader;
