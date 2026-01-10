import { Number as JNumber } from "qjsp:java/lang/number.js";
import { NumberFormatException } from "qjsp:java/lang/numberformatexception.js";

export class Integer extends JNumber {
  constructor(value) {
    super((Number(value) | 0));
  }

  intValue() {
    return this._v | 0;
  }

  longValue() {
    return BigInt(this.intValue());
  }

  static parseInt(s, radix) {
    const r = radix === void 0 ? 10 : (Number(radix) | 0);
    if (!Number.isInteger(r) || r < 2 || r > 36) throw new RangeError("Integer.parseInt: radix must be 2..36");
    const str = String(s).trim();
    if (str.length === 0) throw new NumberFormatException("empty string");
    const n = globalThis.parseInt(str, r);
    if (!Number.isFinite(n)) throw new NumberFormatException("invalid integer");
    return n | 0;
  }

  static valueOf(v) {
    return new Integer(v);
  }

  static toString(i, radix) {
    const r = radix === void 0 ? 10 : (Number(radix) | 0);
    return (Number(i) | 0).toString(r);
  }
}

export default Integer;
