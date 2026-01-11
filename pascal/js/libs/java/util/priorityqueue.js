import { toComparator } from "qjsp:java/util/comparator.js";

export class PriorityQueue {
  constructor(comparator) {
    this._cmp = comparator !== void 0 ? toComparator(comparator) : (a, b) => (a < b ? -1 : a > b ? 1 : 0);
    this._heap = [];
  }

  size() {
    return this._heap.length;
  }

  isEmpty() {
    return this._heap.length === 0;
  }

  peek() {
    return this._heap.length ? this._heap[0] : null;
  }

  offer(e) {
    this._heap.push(e);
    this._siftUp(this._heap.length - 1);
    return true;
  }

  add(e) {
    return this.offer(e);
  }

  poll() {
    const h = this._heap;
    const n = h.length;
    if (n === 0) return null;
    if (n === 1) return h.pop();

    const root = h[0];
    h[0] = h.pop();
    this._siftDown(0);
    return root;
  }

  remove() {
    const v = this.poll();
    if (v === null) throw new Error("PriorityQueue.remove: queue is empty");
    return v;
  }

  clear() {
    this._heap.length = 0;
  }

  toArray() {
    return this._heap.slice();
  }

  _siftUp(i) {
    const h = this._heap;
    const cmp = this._cmp;
    while (i > 0) {
      const p = ((i - 1) / 2) | 0;
      if (cmp(h[i], h[p]) >= 0) break;
      const t = h[i];
      h[i] = h[p];
      h[p] = t;
      i = p;
    }
  }

  _siftDown(i) {
    const h = this._heap;
    const cmp = this._cmp;
    const n = h.length;
    while (true) {
      const l = i * 2 + 1;
      if (l >= n) break;
      const r = l + 1;
      let m = l;
      if (r < n && cmp(h[r], h[l]) < 0) m = r;
      if (cmp(h[m], h[i]) >= 0) break;
      const t = h[i];
      h[i] = h[m];
      h[m] = t;
      i = m;
    }
  }
}

export default PriorityQueue;
