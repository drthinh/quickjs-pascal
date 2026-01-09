export class Boolean {
  constructor(value) {
    this._v = !!value;
  }

  booleanValue() {
    return this._v;
  }

  toString() {
    return this._v ? "true" : "false";
  }

  valueOf() {
    return this._v;
  }

  static parseBoolean(s) {
    return String(s).toLowerCase() === "true";
  }

  static valueOf(v) {
    return new Boolean(v);
  }
}

export default Boolean;
