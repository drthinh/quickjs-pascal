import { Constructor } from "qjsp:java/lang/reflect/constructor.js";
import { Method } from "qjsp:java/lang/reflect/method.js";
import { Field } from "qjsp:java/lang/reflect/field.js";

function isFunction(v) {
  return typeof v === "function";
}

function isObject(v) {
  return v !== null && (typeof v === "object" || typeof v === "function");
}

 function uniquePush(arr, item, keyFn) {
  const k = keyFn(item);
  for (const it of arr) {
    if (keyFn(it) === k) return;
  }
  arr.push(item);
 }

 function normalizeInterfaceSpec(v) {
  if (!v) return null;
  if (typeof v === "string") return v;
  if (typeof v === "function") return v.name || "(anonymous)";
  if (typeof v === "object") {
    if (typeof v.name === "string") return v.name;
    if (typeof v.getName === "function") return String(v.getName());
  }
  return String(v);
 }

 function getInterfaceNames(ctor) {
  const arr = ctor && ctor.__interfaces;
  if (!Array.isArray(arr)) return [];
  const out = [];
  for (const it of arr) {
    const n = normalizeInterfaceSpec(it);
    if (!n) continue;
    if (out.indexOf(n) < 0) out.push(n);
  }
  return out;
 }

 export class Class {
  constructor(ctor, sampleInstance) {
    if (!isFunction(ctor)) throw new TypeError("Class: ctor must be a function");
    this._ctor = ctor;
    this._sample = sampleInstance;
  }

  static of(target) {
    if (!isObject(target)) throw new TypeError("Class.of: target must be object or function");
    if (isFunction(target)) return new Class(target);
    return new Class(target.constructor, target);
  }

  getName() {
    return this._ctor.name || "(anonymous)";
  }

  getSimpleName() {
    return this.getName();
  }

  isInstance(obj) {
    if (!isObject(obj)) return false;
    return obj instanceof this._ctor;
  }

  isAssignableFrom(other) {
    if (!(other instanceof Class)) throw new TypeError("Class.isAssignableFrom: other must be a Class");
    if (this._ctor === other._ctor) return true;
    let cur = other;
    while (cur) {
      if (cur._ctor === this._ctor) return true;
      cur = cur.getSuperclass();
    }

    const want = getInterfaceNames(this._ctor);
    if (want.length > 0) {
      const have = getInterfaceNames(other._ctor);
      for (const n of want) {
        if (have.indexOf(n) < 0) return false;
      }
      return true;
    }

    return false;
  }

  getInterfaces() {
    return getInterfaceNames(this._ctor).map((name) => ({ name }));
  }

  getSuperclass() {
    const proto = this._ctor && this._ctor.prototype ? Object.getPrototypeOf(this._ctor.prototype) : null;
    if (!proto || !proto.constructor || proto === Object.prototype) return null;
    return new Class(proto.constructor);
  }

  getConstructor() {
    return new Constructor(this, this._ctor);
  }

  newInstance(...args) {
    return this.getConstructor().newInstance(...args);
  }

  getDeclaredMethods() {
    const out = [];
    const proto = this._ctor.prototype;
    const names = Object.getOwnPropertyNames(proto);
    for (const name of names) {
      if (name === "constructor") continue;
      const desc = Object.getOwnPropertyDescriptor(proto, name);
      if (!desc) continue;
      const fn = desc.value;
      if (typeof fn === "function") {
        out.push(new Method(this, name, fn, false));
      }
    }
    return out;
  }

  getMethods() {
    const out = [];
    let cur = this;
    while (cur) {
      for (const m of cur.getDeclaredMethods()) {
        uniquePush(out, m, (x) => x.getName());
      }
      cur = cur.getSuperclass();
    }
    return out;
  }

  getDeclaredMethod(name) {
    for (const m of this.getDeclaredMethods()) {
      if (m.getName() === name) return m;
    }
    return null;
  }

  getMethod(name) {
    for (const m of this.getMethods()) {
      if (m.getName() === name) return m;
    }
    return null;
  }

  getDeclaredFields() {
    const out = [];
    const proto = this._ctor.prototype;
    const names = Object.getOwnPropertyNames(proto);
    for (const name of names) {
      if (name === "constructor") continue;
      const desc = Object.getOwnPropertyDescriptor(proto, name);
      if (!desc) continue;
      if (typeof desc.value !== "function") {
        out.push(new Field(this, name, false));
      }
    }
    if (this._sample) {
      for (const name of Object.getOwnPropertyNames(this._sample)) {
        if (name === "constructor") continue;
        const v = this._sample[name];
        if (typeof v !== "function") {
          out.push(new Field(this, name, false));
        }
      }
    }
    return out;
  }

  getFields() {
    const out = [];
    let cur = this;
    while (cur) {
      for (const f of cur.getDeclaredFields()) {
        uniquePush(out, f, (x) => x.getName());
      }
      cur = cur.getSuperclass();
    }
    return out;
  }

  getDeclaredField(name) {
    for (const f of this.getDeclaredFields()) {
      if (f.getName() === name) return f;
    }
    return null;
  }

  getField(name) {
    for (const f of this.getFields()) {
      if (f.getName() === name) return f;
    }
    return null;
  }
 }

 export default Class;
