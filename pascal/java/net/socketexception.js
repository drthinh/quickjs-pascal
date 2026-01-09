import { IOException } from "qjsp:java/io/ioexception.js";

export class SocketException extends IOException {
  constructor(message, cause) {
    super(message, cause);
    this.name = "SocketException";
  }
}

export default SocketException;
