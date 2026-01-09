import { RuntimeException } from "qjsp:java/lang/runtimeexception.js";

export class IndexOutOfBoundsException extends RuntimeException {
  constructor(message, cause) {
    super(message, cause);
    this.name = "IndexOutOfBoundsException";
  }
}

export default IndexOutOfBoundsException;
