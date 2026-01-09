import * as std from "qjs:std";
import { assert } from "qjsp:util";
import { base64FromString, base64ToString, base64EncodeBytes, base64DecodeToBytes, hexEncode, hexDecode } from "qjsp:encoding";

function hr(title) {
  std.printf("\n=== %s ===\n", title);
}

hr("hex");
{
  const u8 = new TextEncoder().encode("hello");
  const h = hexEncode(u8);
  std.printf("hexEncode('hello'): %s\n", h);
  const back = new TextDecoder().decode(hexDecode(h));
  assert(back === "hello", "hex roundtrip failed");
}

hr("base64 (string helpers)");
{
  const b = base64FromString("hello");
  std.printf("base64FromString('hello'): %s\n", b);
  const back = base64ToString(b);
  assert(back === "hello", "base64 string roundtrip failed");
}

hr("base64 (bytes)");
{
  const u8 = new Uint8Array([0, 1, 2, 250, 251, 252, 253, 254, 255]);
  const b = base64EncodeBytes(u8);
  const back = base64DecodeToBytes(b);
  assert(back.length === u8.length, "base64 bytes len mismatch");
  for (let i = 0; i < u8.length; i++) assert(back[i] === u8[i], "base64 bytes mismatch");
}

hr("done");
