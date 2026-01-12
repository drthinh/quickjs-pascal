const _kWriter = Symbol.for("qjsp.java.io.Writer");

export class Writer {
  static [Symbol.hasInstance](instance) {
    return !!(instance && instance[_kWriter]);
  }

  constructor() {
    this[_kWriter] = true;
  }

  write() {
    throw new Error("java.io.Writer.write is not implemented");
  }

  writeChars(cbuf, off, len) {
    if (!Array.isArray(cbuf) && !(cbuf instanceof Uint16Array)) {
      throw new TypeError("Writer.writeChars(cbuf[, off[, len]]): cbuf must be Array or Uint16Array");
    }
    const o = off === void 0 ? 0 : (Number(off) | 0);
    const l = len === void 0 ? (cbuf.length - o) : (Number(len) | 0);
    if (o < 0 || l < 0 || o > cbuf.length || o + l > cbuf.length) throw new RangeError("Writer.writeChars: invalid off/len");

    let s = "";
    if (cbuf instanceof Uint16Array) {
      for (let i = 0; i < l; i++) s += String.fromCharCode(cbuf[o + i]);
    } else {
      for (let i = 0; i < l; i++) s += String(cbuf[o + i]);
    }
    this.write(s);
  }

  flush() {}

  close() {}
}

export default Writer;
