import { Number as JNumber } from "qjsp:java/lang/number.js";

export class Float extends JNumber {
  constructor(value) {
    super(Number(value));
  }

  floatValue() {
    return Number(this._v);
  }

  static parseFloat(s) {
    return globalThis.parseFloat(String(s));
  }

  static isNaN(v) {
    return Number.isNaN(Number(v));
  }

  static valueOf(v) {
    return new Float(v);
  }
}

export default Float;
