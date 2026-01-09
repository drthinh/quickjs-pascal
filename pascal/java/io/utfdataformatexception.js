import { IOException } from "qjsp:java/io/ioexception.js";

export class UTFDataFormatException extends IOException {
  constructor(message, cause) {
    super(message, cause);
    this.name = "UTFDataFormatException";
  }
}

export default UTFDataFormatException;
