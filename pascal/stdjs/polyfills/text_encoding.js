export function installTextEncoding() {
  function __qjsp_utf8_decode(u8) {
    var s = "";
    var i = 0;
    while (i < u8.length) {
      var c0 = u8[i++] & 0xFF;
      if (c0 < 0x80) {
        s += String.fromCharCode(c0);
        continue;
      }
      if ((c0 & 0xE0) === 0xC0) {
        if (i >= u8.length) break;
        var c1 = u8[i++] & 0x3F;
        s += String.fromCharCode(((c0 & 0x1F) << 6) | c1);
        continue;
      }
      if ((c0 & 0xF0) === 0xE0) {
        if (i + 1 > u8.length) break;
        var c1 = u8[i++] & 0x3F;
        var c2 = u8[i++] & 0x3F;
        s += String.fromCharCode(((c0 & 0x0F) << 12) | (c1 << 6) | c2);
        continue;
      }
      if ((c0 & 0xF8) === 0xF0) {
        if (i + 2 > u8.length) break;
        var c1 = u8[i++] & 0x3F;
        var c2 = u8[i++] & 0x3F;
        var c3 = u8[i++] & 0x3F;
        var cp = (((c0 & 0x07) << 18) | (c1 << 12) | (c2 << 6) | c3) - 0x10000;
        s += String.fromCharCode(0xD800 + (cp >> 10), 0xDC00 + (cp & 0x3FF));
        continue;
      }
      s += "\uFFFD";
    }
    return s;
  }

  function __qjsp_utf8_encode(str) {
    var out = [];
    for (var i = 0; i < str.length; i++) {
      var cp = str.charCodeAt(i);
      if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < str.length) {
        var lo = str.charCodeAt(i + 1);
        if (lo >= 0xDC00 && lo <= 0xDFFF) {
          cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
          i++;
        }
      }
      if (cp < 0x80) {
        out.push(cp);
      } else if (cp < 0x800) {
        out.push(0xC0 | (cp >> 6), 0x80 | (cp & 0x3F));
      } else if (cp < 0x10000) {
        out.push(
          0xE0 | (cp >> 12),
          0x80 | ((cp >> 6) & 0x3F),
          0x80 | (cp & 0x3F),
        );
      } else {
        out.push(
          0xF0 | (cp >> 18),
          0x80 | ((cp >> 12) & 0x3F),
          0x80 | ((cp >> 6) & 0x3F),
          0x80 | (cp & 0x3F),
        );
      }
    }
    return new Uint8Array(out);
  }

  if (globalThis.TextDecoder === void 0) {
    globalThis.TextDecoder = function TextDecoder(encoding) {
      this.encoding = (encoding === void 0 ? "utf-8" : String(encoding)).toLowerCase();
      if (this.encoding !== "utf-8" && this.encoding !== "utf8") {
        throw new RangeError("Only utf-8 supported");
      }
    };
    globalThis.TextDecoder.prototype.decode = function (input) {
      if (input === void 0) return "";
      var u8 = input instanceof Uint8Array ? input : new Uint8Array(input);
      return __qjsp_utf8_decode(u8);
    };
  }

  if (globalThis.TextEncoder === void 0) {
    globalThis.TextEncoder = function TextEncoder() {};
    globalThis.TextEncoder.prototype.encode = function (str) {
      return __qjsp_utf8_encode(String(str));
    };
  }
}
