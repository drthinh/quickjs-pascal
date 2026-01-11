import { OutputStream } from "qjsp:java/io/outputstream.js";

function _isOutputStreamLike(v) {
  return v != null &&
    typeof v.write === "function" &&
    typeof v.writeBytes === "function" &&
    typeof v.flush === "function" &&
    typeof v.close === "function";
}

export class DataOutputStream {
  constructor(output) {
    if (!_isOutputStreamLike(output)) throw new TypeError("DataOutputStream(output): output must be OutputStream");
    this._out = output;
    this._tmp = new Uint8Array(8);
    this._dv = new DataView(this._tmp.buffer);
  }

  write(b) {
    this._out.write(b);
  }

  writeBytes(b, off, len) {
    this._out.writeBytes(b, off, len);
  }

  writeBoolean(v) {
    this._out.write(v ? 1 : 0);
  }

  writeByte(v) {
    this._out.write(Number(v) & 0xff);
  }

  writeShort(v) {
    this._dv.setInt16(0, Number(v) | 0, false);
    this._out.writeBytes(this._tmp, 0, 2);
  }

  writeChar(v) {
    this._dv.setUint16(0, Number(v) & 0xffff, false);
    this._out.writeBytes(this._tmp, 0, 2);
  }

  writeInt(v) {
    this._dv.setInt32(0, Number(v) | 0, false);
    this._out.writeBytes(this._tmp, 0, 4);
  }

  writeLong(v) {
    const x = typeof v === "bigint" ? v : BigInt(Math.trunc(Number(v)));
    const hi = Number((x >> 32n) & 0xffffffffn) | 0;
    const lo = Number(x & 0xffffffffn) >>> 0;
    this._dv.setInt32(0, hi, false);
    this._dv.setUint32(4, lo, false);
    this._out.writeBytes(this._tmp, 0, 8);
  }

  writeFloat(v) {
    this._dv.setFloat32(0, Number(v), false);
    this._out.writeBytes(this._tmp, 0, 4);
  }

  writeDouble(v) {
    this._dv.setFloat64(0, Number(v), false);
    this._out.writeBytes(this._tmp, 0, 8);
  }

  flush() {
    this._out.flush();
  }

  close() {
    this._out.close();
  }
}

export default DataOutputStream;
