export class URLEncoder {
  static encode(s, enc) {
    if (enc !== void 0 && enc !== null && String(enc).toLowerCase() !== "utf-8") {
      throw new Error("URLEncoder.encode: only utf-8 is supported");
    }
    // Java URLEncoder uses application/x-www-form-urlencoded semantics.
    return encodeURIComponent(String(s)).replace(/%20/g, "+");
  }
}

export default URLEncoder;
