const _kThrowable = Symbol.for("qjsp.java.lang.Throwable");

export class Throwable extends globalThis.Error {
  static [Symbol.hasInstance](instance) {
    return !!(instance && instance[_kThrowable]);
  }

  constructor(message, cause) {
    super(message === void 0 ? null : String(message));
    try {
      const proto = (typeof new.target === "function" && new.target.prototype) ? new.target.prototype : Throwable.prototype;
      Object.setPrototypeOf(this, proto);
    } catch (e) {
    }
    this[_kThrowable] = true;
    this.name = "Throwable";
    this.cause = cause;
  }
}

export default Throwable;
