export class Field {
  constructor(declaringClass, name, isStatic, typeHint) {
    this._declaringClass = declaringClass;
    this._name = name;
    this._isStatic = !!isStatic;
    this._typeHint = typeHint;
  }

  getName() {
    return this._name;
  }

  getDeclaringClass() {
    return this._declaringClass;
  }

  isStatic() {
    return this._isStatic;
  }

  getType() {
    if (this._typeHint) return this._typeHint;

    let v;
    if (this._isStatic) {
      const ctor = this._declaringClass && this._declaringClass._ctor;
      v = ctor ? ctor[this._name] : undefined;
    } else {
      const sample = this._declaringClass && this._declaringClass._sample;
      v = sample ? sample[this._name] : undefined;
    }

    if (v === null) return "null";
    if (v === undefined) return "undefined";
    const t = typeof v;
    if (t === "string") return "string";
    if (t === "number") return "number";
    if (t === "bigint") return "bigint";
    if (t === "boolean") return "boolean";
    if (t === "function") return "function";
    if (t === "object") return v && v.constructor && v.constructor.name ? v.constructor.name : "object";
    return t;
  }

  get(target) {
    if (this._isStatic) {
      const ctor = this._declaringClass && this._declaringClass._ctor;
      return ctor ? ctor[this._name] : undefined;
    }
    return target ? target[this._name] : undefined;
  }

  set(target, value) {
    if (this._isStatic) {
      const ctor = this._declaringClass && this._declaringClass._ctor;
      if (!ctor) throw new Error("Field.set: missing declaring ctor");
      ctor[this._name] = value;
      return;
    }
    if (!target) throw new Error("Field.set: target is required");
    target[this._name] = value;
  }
}

export default Field;
