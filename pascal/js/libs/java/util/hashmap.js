export class HashMap {
  constructor(initial) {
    this._m = new Map();
    if (initial !== void 0) {
      if (initial instanceof Map) {
        for (const [k, v] of initial.entries()) this._m.set(k, v);
      } else if (Array.isArray(initial)) {
        for (const [k, v] of initial) this._m.set(k, v);
      } else {
        for (const [k, v] of initial) this._m.set(k, v);
      }
    }
  }

  size() {
    return this._m.size;
  }

  isEmpty() {
    return this._m.size === 0;
  }

  get(key) {
    return this._m.get(key);
  }

  put(key, value) {
    const had = this._m.has(key);
    const prev = this._m.get(key);
    this._m.set(key, value);
    return had ? prev : null;
  }

  containsKey(key) {
    return this._m.has(key);
  }

  remove(key) {
    const had = this._m.has(key);
    const prev = this._m.get(key);
    this._m.delete(key);
    return had ? prev : null;
  }

  clear() {
    this._m.clear();
  }

  keySet() {
    return this._m.keys();
  }

  values() {
    return this._m.values();
  }

  entrySet() {
    return this._m.entries();
  }

  [Symbol.iterator]() {
    return this._m[Symbol.iterator]();
  }

  toString() {
    const parts = [];
    for (const [k, v] of this._m.entries()) parts.push(String(k) + "=" + String(v));
    return "{" + parts.join(", ") + "}";
  }
}

export default HashMap;
