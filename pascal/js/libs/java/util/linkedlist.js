import { IndexOutOfBoundsException } from "qjsp:java/lang/indexoutofboundsexception.js";

export class LinkedList {
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

  clear() {
    this._a.length = 0;
  }

  add(e) {
    this._a.push(e);
    return true;
  }

  addFirst(e) {
    this._a.unshift(e);
  }

  addLast(e) {
    this._a.push(e);
  }

  getFirst() {
    if (this._a.length === 0) throw new IndexOutOfBoundsException("empty");
    return this._a[0];
  }

  getLast() {
    if (this._a.length === 0) throw new IndexOutOfBoundsException("empty");
    return this._a[this._a.length - 1];
  }

  peekFirst() {
    return this._a.length === 0 ? null : this._a[0];
  }

  peekLast() {
    return this._a.length === 0 ? null : this._a[this._a.length - 1];
  }

  pollFirst() {
    return this._a.length === 0 ? null : this._a.shift();
  }

  pollLast() {
    return this._a.length === 0 ? null : this._a.pop();
  }

  removeFirst() {
    if (this._a.length === 0) throw new IndexOutOfBoundsException("empty");
    return this._a.shift();
  }

  removeLast() {
    if (this._a.length === 0) throw new IndexOutOfBoundsException("empty");
    return this._a.pop();
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

export default LinkedList;
