import { toU8 } from "qjsp:util/bytes.js";

export function hexEncode(input) {
  const u8 = toU8(input);
  let out = "";
  for (let i = 0; i < u8.length; i++) {
    const v = u8[i].toString(16);
    out += v.length === 1 ? "0" + v : v;
  }
  return out;
}

function hexValue(ch) {
  const c = ch.charCodeAt(0);
  if (c >= 48 && c <= 57) return c - 48;
  if (c >= 65 && c <= 70) return c - 65 + 10;
  if (c >= 97 && c <= 102) return c - 97 + 10;
  return -1;
}

export function hexDecode(hex) {
  const s = String(hex).trim();
  if ((s.length & 1) === 1) {
    throw new TypeError("hex string length must be even");
  }

  const out = new Uint8Array(s.length / 2);
  for (let i = 0, j = 0; i < s.length; i += 2, j++) {
    const hi = hexValue(s[i]);
    const lo = hexValue(s[i + 1]);
    if (hi < 0 || lo < 0) {
      throw new TypeError("invalid hex character");
    }
    out[j] = (hi << 4) | lo;
  }
  return out;
}
