import { toComparator } from "qjsp:java/util/comparator.js";

function _naturalCompare(a, b) {
  return a < b ? -1 : a > b ? 1 : 0;
}

export class TreeMap {
  constructor(comparator) {
    this._cmp = comparator !== void 0 ? toComparator(comparator) : _naturalCompare;
    this._entries = [];
  }

  size() {
    return this._entries.length;
  }

  isEmpty() {
    return this._entries.length === 0;
  }

  clear() {
    this._entries.length = 0;
  }

  comparator() {
    return this._cmp;
  }

  _indexOfKey(key) {
    const a = this._entries;
    const cmp = this._cmp;
    let low = 0;
    let high = a.length - 1;
    while (low <= high) {
      const mid = (low + high) >> 1;
      const c = cmp(a[mid][0], key);
      if (c < 0) low = mid + 1;
      else if (c > 0) high = mid - 1;
      else return mid;
    }
    return -(low + 1);
  }

  containsKey(key) {
    return this._indexOfKey(key) >= 0;
  }

  get(key) {
    const i = this._indexOfKey(key);
    return i >= 0 ? this._entries[i][1] : null;
  }

  put(key, value) {
    const i = this._indexOfKey(key);
    if (i >= 0) {
      const prev = this._entries[i][1];
      this._entries[i][1] = value;
      return prev;
    }
    this._entries.splice(-i - 1, 0, [key, value]);
    return null;
  }

  remove(key) {
    const i = this._indexOfKey(key);
    if (i < 0) return null;
    const prev = this._entries[i][1];
    this._entries.splice(i, 1);
    return prev;
  }

  firstKey() {
    if (!this._entries.length) throw new Error("TreeMap.firstKey: map is empty");
    return this._entries[0][0];
  }

  lastKey() {
    if (!this._entries.length) throw new Error("TreeMap.lastKey: map is empty");
    return this._entries[this._entries.length - 1][0];
  }

  keys() {
    return this._entries.map((e) => e[0]);
  }

  values() {
    return this._entries.map((e) => e[1]);
  }

  entrySet() {
    return this._entries.map((e) => ({ key: e[0], value: e[1] }));
  }

  forEach(fn) {
    for (const [k, v] of this._entries) fn(v, k, this);
  }
}

export default TreeMap;
