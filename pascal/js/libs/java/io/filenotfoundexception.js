import { IOException } from "qjsp:java/io/ioexception.js";

export class FileNotFoundException extends IOException {
  constructor(message, cause) {
    super(message, cause);
    this.name = "FileNotFoundException";
  }
}

export default FileNotFoundException;
