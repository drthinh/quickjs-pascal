import { Throwable } from "qjsp:java/lang/throwable.js";

export class Exception extends Throwable {
  constructor(message, cause) {
    super(message, cause);
    this.name = "Exception";
  }
}

export default Exception;
