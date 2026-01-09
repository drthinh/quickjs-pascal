function _assertFn(fn, name) {
  if (typeof fn !== "function") throw new TypeError(`${name} must be a function`);
}

export function range(start, endExclusive, step) {
  if (endExclusive === void 0) {
    endExclusive = start;
    start = 0;
  }
  step = step === void 0 ? 1 : step;
  if (step === 0) throw new RangeError("range: step must not be 0");

  const out = [];
  if (step > 0) {
    for (let i = start; i < endExclusive; i += step) out.push(i);
  } else {
    for (let i = start; i > endExclusive; i += step) out.push(i);
  }
  return out;
}

export function chunk(array, size) {
  if (!Array.isArray(array)) throw new TypeError("chunk: array must be an Array");
  if (!Number.isFinite(size) || size <= 0) throw new RangeError("chunk: size must be > 0");
  const out = [];
  for (let i = 0; i < array.length; i += size) out.push(array.slice(i, i + size));
  return out;
}

export function partition(array, predicate) {
  if (!Array.isArray(array)) throw new TypeError("partition: array must be an Array");
  _assertFn(predicate, "partition: predicate");
  const t = [];
  const f = [];
  for (const v of array) (predicate(v) ? t : f).push(v);
  return [t, f];
}

export function groupBy(iterable, keyFn) {
  _assertFn(keyFn, "groupBy: keyFn");
  const m = new Map();
  for (const v of iterable) {
    const k = keyFn(v);
    const arr = m.get(k);
    if (arr) arr.push(v);
    else m.set(k, [v]);
  }
  return m;
}

export function indexBy(iterable, keyFn) {
  _assertFn(keyFn, "indexBy: keyFn");
  const m = new Map();
  for (const v of iterable) m.set(keyFn(v), v);
  return m;
}

export function distinct(iterable, keyFn) {
  keyFn = keyFn === void 0 ? (x) => x : keyFn;
  _assertFn(keyFn, "distinct: keyFn");
  const seen = new Set();
  const out = [];
  for (const v of iterable) {
    const k = keyFn(v);
    if (seen.has(k)) continue;
    seen.add(k);
    out.push(v);
  }
  return out;
}

export function toMap(iterable, keyFn, valueFn) {
  _assertFn(keyFn, "toMap: keyFn");
  valueFn = valueFn === void 0 ? (x) => x : valueFn;
  _assertFn(valueFn, "toMap: valueFn");
  const m = new Map();
  for (const v of iterable) m.set(keyFn(v), valueFn(v));
  return m;
}

export function toSet(iterable) {
  return new Set(iterable);
}

export function first(iterable, predicate) {
  if (predicate !== void 0) _assertFn(predicate, "first: predicate");
  for (const v of iterable) {
    if (!predicate || predicate(v)) return v;
  }
  return undefined;
}

export function last(iterable, predicate) {
  if (predicate !== void 0) _assertFn(predicate, "last: predicate");
  let found = false;
  let out;
  for (const v of iterable) {
    if (!predicate || predicate(v)) {
      found = true;
      out = v;
    }
  }
  return found ? out : undefined;
}

export function count(iterable, predicate) {
  if (predicate !== void 0) _assertFn(predicate, "count: predicate");
  let n = 0;
  for (const v of iterable) {
    if (!predicate || predicate(v)) n++;
  }
  return n;
}

export function mapValues(map, mapper) {
  if (!(map instanceof Map)) throw new TypeError("mapValues: map must be a Map");
  _assertFn(mapper, "mapValues: mapper");
  const out = new Map();
  for (const [k, v] of map.entries()) out.set(k, mapper(v, k));
  return out;
}

export function filterValues(map, predicate) {
  if (!(map instanceof Map)) throw new TypeError("filterValues: map must be a Map");
  _assertFn(predicate, "filterValues: predicate");
  const out = new Map();
  for (const [k, v] of map.entries()) {
    if (predicate(v, k)) out.set(k, v);
  }
  return out;
}
