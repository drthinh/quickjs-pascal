import { NumberFormatException } from "qjsp:java/lang/numberformatexception.js";

export class Long {
  constructor(value) {
    this._v = typeof value === "bigint" ? value : BigInt(Math.trunc(Number(value)));
  }

  longValue() {
    return this._v;
  }

  intValue() {
    return Number(this._v & 0xffffffffn) | 0;
  }

  doubleValue() {
    return Number(this._v);
  }

  toString() {
    return this._v.toString(10);
  }

  valueOf() {
    return this._v;
  }

  static parseLong(s, radix) {
    const r = radix === void 0 ? 10 : (Number(radix) | 0);
    if (!Number.isInteger(r) || r < 2 || r > 36) throw new RangeError("Long.parseLong: radix must be 2..36");
    const str = String(s).trim();
    if (str.length === 0) throw new NumberFormatException("empty string");
    let sign = 1n;
    let i = 0;
    if (str[0] === "+") i = 1;
    else if (str[0] === "-") {
      sign = -1n;
      i = 1;
    }
    let n = 0n;
    const base = BigInt(r);
    for (; i < str.length; i++) {
      const ch = str[i];
      const d = parseInt(ch, r);
      if (!Number.isFinite(d) || d < 0 || d >= r) throw new NumberFormatException("invalid long");
      n = n * base + BigInt(d);
    }
    return n * sign;
  }

  static valueOf(v) {
    return new Long(v);
  }

  static toString(v, radix) {
    const r = radix === void 0 ? 10 : (Number(radix) | 0);
    const x = typeof v === "bigint" ? v : BigInt(Math.trunc(Number(v)));
    return x.toString(r);
  }
}

export default Long;
