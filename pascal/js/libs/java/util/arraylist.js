import { IndexOutOfBoundsException } from "qjsp:java/lang/indexoutofboundsexception.js";

export class ArrayList {
  constructor(initial) {
    if (initial === void 0) this._a = [];
    else if (Array.isArray(initial)) this._a = initial.slice();
    else this._a = Array.from(initial);
  }

  size() {
    return this._a.length;
  }

  isEmpty() {
    return this._a.length === 0;
  }

  get(index) {
    const i = Number(index) | 0;
    if (i < 0 || i >= this._a.length) throw new IndexOutOfBoundsException("index: " + i);
    return this._a[i];
  }

  set(index, element) {
    const i = Number(index) | 0;
    if (i < 0 || i >= this._a.length) throw new IndexOutOfBoundsException("index: " + i);
    const old = this._a[i];
    this._a[i] = element;
    return old;
  }

  add(element) {
    this._a.push(element);
    return true;
  }

  addAll(iterable) {
    for (const v of iterable) this._a.push(v);
    return true;
  }

  remove(indexOrElement) {
    if (typeof indexOrElement === "number") {
      const i = Number(indexOrElement) | 0;
      if (i < 0 || i >= this._a.length) throw new IndexOutOfBoundsException("index: " + i);
      const old = this._a[i];
      this._a.splice(i, 1);
      return old;
    }
    const idx = this._a.indexOf(indexOrElement);
    if (idx < 0) return false;
    this._a.splice(idx, 1);
    return true;
  }

  clear() {
    this._a.length = 0;
  }

  toArray() {
    return this._a.slice();
  }

  [Symbol.iterator]() {
    return this._a[Symbol.iterator]();
  }

  toString() {
    return "[" + this._a.map((v) => String(v)).join(", ") + "]";
  }
}

export default ArrayList;
