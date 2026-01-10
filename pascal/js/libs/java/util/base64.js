import { toU8 } from "qjsp:util/bytes.js";
import { base64EncodeBytes, base64DecodeToBytes } from "qjsp:encoding/base64.js";

function _encodeToString(bytes) {
  return base64EncodeBytes(toU8(bytes));
}

function _encode(bytes) {
  const s = _encodeToString(bytes);
  return new TextEncoder().encode(s);
}

function _decode(str) {
  return base64DecodeToBytes(String(str));
}

function _wrapEncoder() {
  return Object.freeze({
    encodeToString(bytes) {
      return _encodeToString(bytes);
    },
    encode(bytes) {
      return _encode(bytes);
    },
  });
}

function _wrapDecoder() {
  return Object.freeze({
    decode(str) {
      return _decode(str);
    },
  });
}

export const Base64 = Object.freeze({
  getEncoder() {
    return _wrapEncoder();
  },
  getDecoder() {
    return _wrapDecoder();
  },
});
