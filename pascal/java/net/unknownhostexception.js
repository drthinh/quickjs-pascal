import { IOException } from "qjsp:java/io/ioexception.js";

export class UnknownHostException extends IOException {
  constructor(message, cause) {
    super(message, cause);
    this.name = "UnknownHostException";
  }
}

export default UnknownHostException;
