import { readTextFile, exists } from "qjsp:io/fs.js";
import { deepMergeAll } from "qjsp:config/merge.js";

export function loadJsonFile(path, options) {
  const opts = options || {};
  const p = String(path);

  if (!exists(p)) {
    if (opts.optional) return null;
    throw new Error(`loadJsonFile: not found ${p}`);
  }

  const text = readTextFile(p);
  if (text.trim() === "") {
    if (opts.allowEmpty) return {};
    throw new Error(`loadJsonFile: empty ${p}`);
  }

  try {
    return JSON.parse(text);
  } catch (e) {
    throw new Error(`loadJsonFile: failed to parse ${p}: ${e && e.message ? e.message : String(e)}`);
  }
}

export function loadAndMergeJsonFiles(paths, options) {
  const opts = options || {};
  if (!Array.isArray(paths)) throw new TypeError("loadAndMergeJsonFiles: paths must be array");

  const objs = [];
  for (const p0 of paths) {
    const p = String(p0);
    const obj = loadJsonFile(p, { optional: !!opts.optional, allowEmpty: !!opts.allowEmpty });
    if (obj !== null) objs.push(obj);
  }

  if (opts.merge === "shallow") {
    return Object.assign({}, ...objs);
  }

  return deepMergeAll(...objs);
}
