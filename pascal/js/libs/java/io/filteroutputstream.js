import { OutputStream } from "qjsp:java/io/outputstream.js";

function _isOutputStreamLike(v) {
  return v != null &&
    typeof v.write === "function" &&
    typeof v.writeBytes === "function" &&
    typeof v.flush === "function" &&
    typeof v.close === "function";
}

export class FilterOutputStream extends OutputStream {
  constructor(output) {
    super();
    if (!_isOutputStreamLike(output)) throw new TypeError("FilterOutputStream(output): output must be OutputStream");
    this._out = output;
  }

  write(b) {
    this._out.write(b);
  }

  writeBytes(b, off, len) {
    this._out.writeBytes(b, off, len);
  }

  flush() {
    this._out.flush();
  }

  close() {
    this._out.close();
  }
}

export default FilterOutputStream;
