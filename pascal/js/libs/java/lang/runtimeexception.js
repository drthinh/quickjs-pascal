import { Exception } from "qjsp:java/lang/exception.js";

export class RuntimeException extends Exception {
  constructor(message, cause) {
    super(message, cause);
    this.name = "RuntimeException";
  }
}

export default RuntimeException;
