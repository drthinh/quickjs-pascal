function isPlainObject(v) {
  if (v === null || typeof v !== "object") return false;
  const proto = Object.getPrototypeOf(v);
  return proto === Object.prototype || proto === null;
}

export function deepMerge(target, source) {
  if (!isPlainObject(target) || !isPlainObject(source)) {
    return source;
  }

  const out = { ...target };
  for (const [k, sv] of Object.entries(source)) {
    const tv = out[k];
    if (isPlainObject(tv) && isPlainObject(sv)) {
      out[k] = deepMerge(tv, sv);
    } else {
      out[k] = sv;
    }
  }
  return out;
}

export function deepMergeAll(...objects) {
  let out = {};
  for (const obj of objects) {
    if (obj === void 0 || obj === null) continue;
    if (!isPlainObject(obj)) throw new TypeError("deepMergeAll: expected plain object");
    out = deepMerge(out, obj);
  }
  return out;
}
