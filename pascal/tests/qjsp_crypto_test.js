import * as crypto from "qjsp:crypto/index.js";

function assertEq(a, b, msg) {
  if (a !== b) throw new Error((msg ? msg + ": " : "") + `assertEq failed: ${a} !== ${b}`);
}

// Test vector: sha256("")
assertEq(
  crypto.sha256Hex(""),
  "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "sha256Hex(\"\")"
);

// base64 roundtrip for bytes [0,1,2,3]
const bytes = new Uint8Array([0, 1, 2, 3]);
const b64 = crypto.base64Encode(bytes);
const ab = crypto.base64Decode(b64);
const out = new Uint8Array(ab);
assertEq(out.length, bytes.length, "base64Decode length");
for (let i = 0; i < out.length; i++) {
  assertEq(out[i], bytes[i], `base64 roundtrip byte[${i}]`);
}

print("qjsp_crypto_test.js OK");
