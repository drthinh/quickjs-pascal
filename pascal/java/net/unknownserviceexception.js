import { IOException } from "qjsp:java/io/ioexception.js";

export class UnknownServiceException extends IOException {
  constructor(message, cause) {
    super(message, cause);
    this.name = "UnknownServiceException";
  }
}

export default UnknownServiceException;
