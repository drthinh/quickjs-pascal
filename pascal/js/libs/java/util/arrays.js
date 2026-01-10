export class Arrays {
  static asList() {
    return Array.prototype.slice.call(arguments);
  }

  static copyOf(array, newLength) {
    const arr = Array.isArray(array) ? array : Array.from(array);
    const n = Number(newLength) | 0;
    if (n < 0) throw new RangeError("Arrays.copyOf: newLength must be >= 0");
    const out = new Array(n);
    for (let i = 0; i < n; i++) out[i] = i < arr.length ? arr[i] : null;
    return out;
  }

  static equals(a, b) {
    if (a === b) return true;
    if (!a || !b) return false;
    const aa = Array.isArray(a) ? a : Array.from(a);
    const bb = Array.isArray(b) ? b : Array.from(b);
    if (aa.length !== bb.length) return false;
    for (let i = 0; i < aa.length; i++) if (aa[i] !== bb[i]) return false;
    return true;
  }

  static fill(array, value, fromIndex, toIndex) {
    const arr = Array.isArray(array) ? array : Array.from(array);
    const start = fromIndex === void 0 ? 0 : (Number(fromIndex) | 0);
    const end = toIndex === void 0 ? arr.length : (Number(toIndex) | 0);
    for (let i = start; i < end; i++) arr[i] = value;
    return arr;
  }
}

export default Arrays;
