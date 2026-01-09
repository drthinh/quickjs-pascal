import { IOException } from "qjsp:java/io/ioexception.js";

export class ProtocolException extends IOException {
  constructor(message, cause) {
    super(message, cause);
    this.name = "ProtocolException";
  }
}

export default ProtocolException;
