import { Exception } from "qjsp:java/lang/exception.js";

export class IOException extends Exception {
  constructor(message, cause) {
    super(message, cause);
    this.name = "IOException";
  }
}

export default IOException;
