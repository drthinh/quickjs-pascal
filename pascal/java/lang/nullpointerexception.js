import { RuntimeException } from "qjsp:java/lang/runtimeexception.js";

export class NullPointerException extends RuntimeException {
  constructor(message, cause) {
    super(message, cause);
    this.name = "NullPointerException";
  }
}

export default NullPointerException;
