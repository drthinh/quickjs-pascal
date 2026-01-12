import { net } from "qjsp:index.js";

function assert(cond, msg) {
  if (!cond) throw new Error(msg || "assert failed");
}

function getErrCode(e) {
  try {
    return e && typeof e === "object" ? e.code : void 0;
  } catch (_) {
    return void 0;
  }
}

// This test is designed to be deterministic and not require network access.
// With host policy enabled, requests outside allowlist should fail before network.
{
  let ok = false;
  try {
    net.http.get("https://google.com", { responseType: "text" });
  } catch (e) {
    ok = getErrCode(e) === "QJSP_E_HTTP_HOST_DENIED";
  }
  assert(ok, "expected host deny for google.com");
}

// Timeout policy should fail deterministically.
{
  let ok = false;
  try {
    net.http.get("https://example.com", { timeoutMs: 999999, responseType: "text" });
  } catch (e) {
    ok = getErrCode(e) === "QJSP_E_HTTP_LIMIT_DENIED";
  }
  assert(ok, "expected timeout limit deny");
}

console.log("http policy test OK");
