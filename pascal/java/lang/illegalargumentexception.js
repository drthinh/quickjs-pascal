import { RuntimeException } from "qjsp:java/lang/runtimeexception.js";

export class IllegalArgumentException extends RuntimeException {
  constructor(message, cause) {
    super(message, cause);
    this.name = "IllegalArgumentException";
  }
}

export default IllegalArgumentException;
