import { installTextEncoding } from "qjsp:polyfills/text_encoding.js";
import * as os from "qjs:os";
import { URL, URLSearchParams } from "qjsp:url/url.js";
import { installFetch } from "qjsp:net/fetch.js";

export function installRuntimeGlobals() {
  installTextEncoding();

  if (globalThis.URL === void 0) globalThis.URL = URL;
  if (globalThis.URLSearchParams === void 0) globalThis.URLSearchParams = URLSearchParams;
  installFetch();

  if (globalThis.setTimeout === void 0 ||
      globalThis.clearTimeout === void 0 ||
      globalThis.setInterval === void 0 ||
      globalThis.clearInterval === void 0) {
    if (globalThis.setTimeout === void 0) globalThis.setTimeout = os.setTimeout;
    if (globalThis.clearTimeout === void 0) globalThis.clearTimeout = os.clearTimeout;
    if (globalThis.setInterval === void 0) globalThis.setInterval = os.setInterval;
    if (globalThis.clearInterval === void 0) globalThis.clearInterval = os.clearInterval;
  }
}

installRuntimeGlobals();
