export class Objects {
  static requireNonNull(obj, message) {
    if (obj === null || obj === undefined) throw new TypeError(message || "null");
    return obj;
  }

  static equals(a, b) {
    return a === b;
  }

  static hashCode(obj) {
    if (obj === null || obj === undefined) return 0;
    if (typeof obj === "number") return obj | 0;
    if (typeof obj === "bigint") return Number(obj & 0xffffffffn) | 0;
    if (typeof obj === "string") {
      let h = 0;
      for (let i = 0; i < obj.length; i++) h = ((h * 31) | 0) + obj.charCodeAt(i);
      return h | 0;
    }
    if (typeof obj.hashCode === "function") return obj.hashCode() | 0;
    return 0;
  }

  static toString(obj, nullDefault) {
    if (obj === null || obj === undefined) return nullDefault === void 0 ? "null" : String(nullDefault);
    return String(obj);
  }
}

export default Objects;
