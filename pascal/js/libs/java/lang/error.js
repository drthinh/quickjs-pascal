import { Throwable } from "qjsp:java/lang/throwable.js";

export class Error extends Throwable {
  constructor(message, cause) {
    super(message, cause);
    this.name = "Error";
  }
}

export default Error;
