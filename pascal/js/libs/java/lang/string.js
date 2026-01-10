export class String {
  constructor(value) {
    if (value instanceof String) this._s = value._s;
    else if (value === void 0) this._s = "";
    else this._s = globalThis.String(value);
  }

  length() { return this._s.length; }
  charAt(i) { return this._s.charAt(Number(i)); }
  substring(begin, end) {
    const b = Number(begin);
    if (end === void 0) return new String(this._s.substring(b));
    return new String(this._s.substring(b, Number(end)));
  }
  concat(str) { return new String(this._s + globalThis.String(str instanceof String ? str._s : str)); }
  replace(oldCh, newCh) {
    return new String(this._s.split(globalThis.String(oldCh)).join(globalThis.String(newCh)));
  }
  toLowerCase() { return new String(this._s.toLowerCase()); }
  toUpperCase() { return new String(this._s.toUpperCase()); }
  trim() { return new String(this._s.trim()); }
  toString() { return this._s; }
  valueOf() { return this._s; }

  equals(other) {
    const o = other instanceof String ? other._s : (other === null || other === void 0 ? null : globalThis.String(other));
    return o !== null && this._s === o;
  }
  equalsIgnoreCase(other) {
    const o = other instanceof String ? other._s : (other === null || other === void 0 ? null : globalThis.String(other));
    return o !== null && this._s.toLowerCase() === o.toLowerCase();
  }
  compareTo(other) {
    const o = other instanceof String ? other._s : globalThis.String(other);
    if (this._s === o) return 0;
    return this._s < o ? -1 : 1;
  }
  startsWith(prefix) { return this._s.startsWith(globalThis.String(prefix instanceof String ? prefix._s : prefix)); }
  endsWith(suffix) { return this._s.endsWith(globalThis.String(suffix instanceof String ? suffix._s : suffix)); }
  indexOf(x, fromIndex) {
    const fi = fromIndex === void 0 ? 0 : Number(fromIndex);
    return this._s.indexOf(globalThis.String(x instanceof String ? x._s : x), fi);
  }
  lastIndexOf(x, fromIndex) {
    const fi = fromIndex === void 0 ? this._s.length : Number(fromIndex);
    return this._s.lastIndexOf(globalThis.String(x instanceof String ? x._s : x), fi);
  }

  static valueOf(x) { return new String(x); }
}

export default String;
