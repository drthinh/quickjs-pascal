export class StringBuffer {
  constructor(initial) {
    this._s = initial === void 0 ? "" : String(initial);
  }

  length() {
    return this._s.length;
  }

  toString() {
    return this._s;
  }

  append(x) {
    this._s += String(x);
    return this;
  }

  charAt(index) {
    const i = Number(index) | 0;
    if (i < 0 || i >= this._s.length) throw new RangeError("StringBuffer.charAt: index out of range");
    return this._s.charAt(i);
  }

  setLength(newLength) {
    const n = Number(newLength) | 0;
    if (n < 0) throw new RangeError("StringBuffer.setLength: newLength must be >= 0");
    if (n <= this._s.length) this._s = this._s.slice(0, n);
    else this._s = this._s + "\0".repeat(n - this._s.length);
  }

  insert(index, str) {
    const i = Number(index) | 0;
    if (i < 0 || i > this._s.length) throw new RangeError("StringBuffer.insert: index out of range");
    const t = String(str);
    this._s = this._s.slice(0, i) + t + this._s.slice(i);
    return this;
  }

  delete(start, end) {
    const s = Number(start) | 0;
    const e = end === void 0 ? this._s.length : (Number(end) | 0);
    if (s < 0 || e < s || s > this._s.length) throw new RangeError("StringBuffer.delete: invalid range");
    const ee = e > this._s.length ? this._s.length : e;
    this._s = this._s.slice(0, s) + this._s.slice(ee);
    return this;
  }

  reverse() {
    this._s = Array.from(this._s).reverse().join("");
    return this;
  }
}

export default StringBuffer;
