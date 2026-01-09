import { IOException } from "qjsp:java/io/ioexception.js";

export class EOFException extends IOException {
  constructor(message, cause) {
    super(message, cause);
    this.name = "EOFException";
  }
}

export default EOFException;
