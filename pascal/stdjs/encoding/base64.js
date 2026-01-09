import { toU8 } from "qjsp:util/bytes.js";

const B64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

export function base64EncodeBytes(input) {
  const u8 = toU8(input);
  let out = "";

  for (let i = 0; i < u8.length; i += 3) {
    const a = u8[i];
    const b = (i + 1 < u8.length) ? u8[i + 1] : 0;
    const c = (i + 2 < u8.length) ? u8[i + 2] : 0;

    const n = (a << 16) | (b << 8) | c;

    out += B64_ALPHABET[(n >> 18) & 63];
    out += B64_ALPHABET[(n >> 12) & 63];
    out += (i + 1 < u8.length) ? B64_ALPHABET[(n >> 6) & 63] : "=";
    out += (i + 2 < u8.length) ? B64_ALPHABET[n & 63] : "=";
  }

  return out;
}

function b64Index(ch) {
  return B64_ALPHABET.indexOf(ch);
}

export function base64DecodeToBytes(b64) {
  const s = String(b64).trim();
  if (s.length === 0) return new Uint8Array(0);
  if ((s.length & 3) !== 0) {
    throw new TypeError("bad base64 length");
  }

  let pad = 0;
  if (s.endsWith("==")) pad = 2;
  else if (s.endsWith("=")) pad = 1;

  const outLen = (s.length / 4) * 3 - pad;
  const out = new Uint8Array(outLen);

  let j = 0;
  for (let i = 0; i < s.length; i += 4) {
    const c0 = s[i];
    const c1 = s[i + 1];
    const c2 = s[i + 2];
    const c3 = s[i + 3];

    const a = b64Index(c0);
    const b = b64Index(c1);
    const c = c2 === "=" ? 0 : b64Index(c2);
    const d = c3 === "=" ? 0 : b64Index(c3);

    if (a < 0 || b < 0 || (c2 !== "=" && c < 0) || (c3 !== "=" && d < 0)) {
      throw new TypeError("bad base64 character");
    }

    const n = (a << 18) | (b << 12) | (c << 6) | d;

    if (j < outLen) out[j++] = (n >> 16) & 255;
    if (j < outLen) out[j++] = (n >> 8) & 255;
    if (j < outLen) out[j++] = n & 255;
  }

  return out;
}

export function base64FromString(text) {
  const u8 = new TextEncoder().encode(String(text));
  return base64EncodeBytes(u8);
}

export function base64ToString(b64) {
  const u8 = base64DecodeToBytes(b64);
  return new TextDecoder().decode(u8);
}
