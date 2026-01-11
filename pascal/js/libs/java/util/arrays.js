import { toComparator } from "qjsp:java/util/comparator.js";

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

  static sort(array, comparator) {
    if (!Array.isArray(array)) throw new TypeError("Arrays.sort: array must be an Array");
    if (comparator !== void 0) {
      const cmp = toComparator(comparator);
      array.sort((a, b) => cmp(a, b));
    } else {
      array.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
    }
    return array;
  }

  static binarySearch(array, key, comparator) {
    const arr = Array.isArray(array) ? array : Array.from(array);
    const cmp = comparator ? toComparator(comparator) : (a, b) => (a < b ? -1 : a > b ? 1 : 0);
    let low = 0;
    let high = arr.length - 1;
    while (low <= high) {
      const mid = (low + high) >> 1;
      const c = cmp(arr[mid], key);
      if (c < 0) {
        low = mid + 1;
      } else if (c > 0) {
        high = mid - 1;
      } else {
        return mid;
      }
    }
    return -(low + 1);
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
