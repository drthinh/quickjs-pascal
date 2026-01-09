export class Number {
  constructor(value) {
    this._v = Number(value);
  }

  intValue() {
    return this._v | 0;
  }

  longValue() {
    return BigInt(Math.trunc(this._v));
  }

  floatValue() {
    return Number(this._v);
  }

  doubleValue() {
    return Number(this._v);
  }

  toString() {
    return String(this._v);
  }
}

export default Number;
