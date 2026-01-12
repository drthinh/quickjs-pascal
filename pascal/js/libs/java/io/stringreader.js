import { Reader } from "qjsp:java/io/reader.js";

export class StringReader extends Reader {
  constructor(str) {
    super();
    this._s = String(str);
    this._pos = 0;
    this._closed = false;
  }

  read() {
    if (this._closed) throw new Error("StringReader is closed");
    if (this._pos >= this._s.length) return -1;
    return this._s.charCodeAt(this._pos++);
  }

  close() {
    this._closed = true;
  }
}

export default StringReader;
