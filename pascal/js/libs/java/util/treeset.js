import { TreeMap } from "qjsp:java/util/treemap.js";

export class TreeSet {
  constructor(comparator) {
    this._m = new TreeMap(comparator);
  }

  size() {
    return this._m.size();
  }

  isEmpty() {
    return this._m.isEmpty();
  }

  clear() {
    this._m.clear();
  }

  contains(e) {
    return this._m.containsKey(e);
  }

  add(e) {
    const prev = this._m.put(e, true);
    return prev === null;
  }

  remove(e) {
    const prev = this._m.remove(e);
    return prev !== null;
  }

  first() {
    return this._m.firstKey();
  }

  last() {
    return this._m.lastKey();
  }

  toArray() {
    return this._m.keys();
  }
}

export default TreeSet;
