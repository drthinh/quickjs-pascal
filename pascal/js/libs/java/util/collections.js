export class Collections {
  static emptyList() {
    return Object.freeze([]);
  }

  static singletonList(obj) {
    return Object.freeze([obj]);
  }

  static unmodifiableList(list) {
    return Object.freeze(Array.isArray(list) ? list.slice() : Array.from(list));
  }

  static sort(list, comparator) {
    if (!Array.isArray(list)) throw new TypeError("Collections.sort: list must be an Array");
    if (comparator !== void 0) {
      if (typeof comparator !== "function") throw new TypeError("Collections.sort: comparator must be a function");
      list.sort((a, b) => comparator(a, b));
    } else {
      list.sort();
    }
  }
}

export default Collections;
