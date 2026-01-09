export class HashSet {
  constructor(initial) {
    this._s = new Set();
    if (initial !== void 0) {
      for (const v of initial) this._s.add(v);
    }
  }

  size() {
    return this._s.size;
  }

  isEmpty() {
    return this._s.size === 0;
  }

  add(value) {
    const had = this._s.has(value);
    this._s.add(value);
    return !had;
  }

  contains(value) {
    return this._s.has(value);
  }

  remove(value) {
    return this._s.delete(value);
  }

  clear() {
    this._s.clear();
  }

  toArray() {
    return Array.from(this._s);
  }

  [Symbol.iterator]() {
    return this._s[Symbol.iterator]();
  }

  toString() {
    return "[" + Array.from(this._s).map((v) => String(v)).join(", ") + "]";
  }
}

export default HashSet;
