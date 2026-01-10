import { InputStream } from "qjsp:java/io/inputstream.js";

export class FilterInputStream extends InputStream {
  constructor(input) {
    super();
    if (!(input instanceof InputStream)) throw new TypeError("FilterInputStream(input): input must be InputStream");
    this._in = input;
  }

  read() {
    return this._in.read();
  }

  readBytes(b, off, len) {
    return this._in.readBytes(b, off, len);
  }

  skip(n) {
    return this._in.skip(n);
  }

  available() {
    return this._in.available();
  }

  close() {
    this._in.close();
  }

  markSupported() {
    return typeof this._in.markSupported === "function" ? this._in.markSupported() : false;
  }

  mark(readlimit) {
    if (typeof this._in.mark === "function") this._in.mark(readlimit);
  }

  reset() {
    if (typeof this._in.reset === "function") return this._in.reset();
    throw new Error("java.io.FilterInputStream.reset is not supported");
  }
}

export default FilterInputStream;
