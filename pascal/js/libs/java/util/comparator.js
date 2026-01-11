function _naturalCompare(a, b) {
  return a < b ? -1 : a > b ? 1 : 0;
}

function _wrapSyncCompare(fn) {
  return (a, b) => {
    const r = fn(a, b);
    if (r && typeof r.then === "function") {
      throw new TypeError("Comparator.compare: async comparator not supported");
    }
    return Number(r) | 0;
  };
}

export function toComparator(comparator) {
  if (comparator === void 0 || comparator === null) return _wrapSyncCompare(_naturalCompare);
  if (typeof comparator === "function") return _wrapSyncCompare(comparator);
  if (typeof comparator === "object" && typeof comparator.compare === "function") {
    return _wrapSyncCompare((a, b) => comparator.compare(a, b));
  }
  throw new TypeError("Comparator: comparator must be a function or an object with compare(a,b)");
}

export class Comparator {
  constructor(compareFn) {
    if (typeof compareFn !== "function") throw new TypeError("Comparator: compareFn must be a function");
    this._cmp = toComparator(compareFn);
  }

  compare(a, b) {
    return this._cmp(a, b);
  }

  reversed() {
    const base = this._cmp;
    return new Comparator((a, b) => base(b, a));
  }

  thenComparing(other) {
    const base = this._cmp;
    const next = toComparator(other);
    return new Comparator((a, b) => {
      const r = base(a, b);
      return r !== 0 ? r : next(a, b);
    });
  }

  static naturalOrder() {
    return new Comparator(_naturalCompare);
  }

  static reverseOrder() {
    return Comparator.naturalOrder().reversed();
  }
}

export default Comparator;
