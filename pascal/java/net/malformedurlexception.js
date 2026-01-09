import { IOException } from "qjsp:java/io/ioexception.js";

export class MalformedURLException extends IOException {
  constructor(message, cause) {
    super(message, cause);
    this.name = "MalformedURLException";
  }
}

export default MalformedURLException;
