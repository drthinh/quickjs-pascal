export class OutputStream {
  constructor() {}

  write(b) {
    throw new Error("java.io.OutputStream.write is not implemented");
  }

  writeBytes(b, off, len) {
    if (b instanceof Uint8Array) {
      const o = off === void 0 ? 0 : (Number(off) | 0);
      const l = len === void 0 ? (b.length - o) : (Number(len) | 0);
      if (o < 0 || l < 0 || o > b.length || o + l > b.length) throw new RangeError("OutputStream.writeBytes: invalid off/len");
      for (let i = 0; i < l; i++) this.write(b[o + i]);
      return;
    }

    // If user passes a single number, treat it as write(int).
    if (typeof b === "number") {
      this.write(b);
      return;
    }

    throw new TypeError("OutputStream.writeBytes(b[, off[, len]]): b must be Uint8Array");
  }

  flush() {}

  close() {}
}

export default OutputStream;
