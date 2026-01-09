import { IOException } from "qjsp:java/io/ioexception.js";

export class InterruptedIOException extends IOException {
  constructor(message, cause) {
    super(message, cause);
    this.name = "InterruptedIOException";
  }
}

export default InterruptedIOException;
