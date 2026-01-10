import { Number as JNumber } from "qjsp:java/lang/number.js";

export class Double extends JNumber {
  constructor(value) {
    super(Number(value));
  }

  doubleValue() {
    return Number(this._v);
  }

  static parseDouble(s) {
    return Number(String(s));
  }

  static isNaN(v) {
    return Number.isNaN(Number(v));
  }

  static isInfinite(v) {
    const n = Number(v);
    return n === Infinity || n === -Infinity;
  }

  static valueOf(v) {
    return new Double(v);
  }
}

export default Double;
