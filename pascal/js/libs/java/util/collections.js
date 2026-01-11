import { Arrays } from "qjsp:java/util/arrays.js";
import { toComparator } from "qjsp:java/util/comparator.js";

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
      const cmp = toComparator(comparator);
      list.sort((a, b) => cmp(a, b));
    } else {
      list.sort();
    }
  }

  static reverse(list) {
    if (!Array.isArray(list)) throw new TypeError("Collections.reverse: list must be an Array");
    list.reverse();
  }

  static rotate(list, distance) {
    if (!Array.isArray(list)) throw new TypeError("Collections.rotate: list must be an Array");
    const n = list.length;
    if (n <= 1) return;
    let k = Number(distance) | 0;
    k %= n;
    if (k < 0) k += n;
    if (k === 0) return;
    const tail = list.splice(n - k, k);
    list.unshift.apply(list, tail);
  }

  static shuffle(list, random) {
    if (!Array.isArray(list)) throw new TypeError("Collections.shuffle: list must be an Array");
    const rnd = random ? random : Math;
    const next = typeof rnd.nextDouble === "function" ? () => rnd.nextDouble() : () => rnd.random();
    for (let i = list.length - 1; i > 0; i--) {
      const j = (next() * (i + 1)) | 0;
      const t = list[i];
      list[i] = list[j];
      list[j] = t;
    }
  }

  static binarySearch(list, key, comparator) {
    if (!Array.isArray(list)) throw new TypeError("Collections.binarySearch: list must be an Array");
    return Arrays.binarySearch(list, key, comparator);
  }
}

export default Collections;
