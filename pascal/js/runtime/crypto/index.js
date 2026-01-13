const nativeCrypto = globalThis.__qjsp_native_crypto;

export function sha256Hex(data) {
  if (!nativeCrypto || typeof nativeCrypto.sha256Hex !== "function") {
    throw new Error("crypto.sha256Hex: native shim not installed");
  }
  return nativeCrypto.sha256Hex(data);
}

export function base64Encode(data) {
  if (!nativeCrypto || typeof nativeCrypto.base64Encode !== "function") {
    throw new Error("crypto.base64Encode: native shim not installed");
  }
  return nativeCrypto.base64Encode(data);
}

export function base64Decode(str) {
  if (!nativeCrypto || typeof nativeCrypto.base64Decode !== "function") {
    throw new Error("crypto.base64Decode: native shim not installed");
  }
  return nativeCrypto.base64Decode(String(str));
}
