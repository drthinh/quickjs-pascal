export class Throwable extends globalThis.Error {
  constructor(message, cause) {
    super(message === void 0 ? null : String(message));
    this.name = "Throwable";
    this.cause = cause;
  }
}

export default Throwable;
