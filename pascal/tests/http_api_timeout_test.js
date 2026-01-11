import { net } from "qjsp:index.js";

function nowMs() {
  return Date.now();
}

function runOne(url, timeoutMs) {
  const t0 = nowMs();
  try {
    const r = net.http.get(url, {
      responseType: "text",
      timeoutMs,
      followRedirects: true,
    });

    const txt = r.text();
    const dt = nowMs() - t0;

    console.log("OK", url);
    console.log("status", r.status, "ms", dt, "bytes", typeof txt === "string" ? txt.length : -1);
    console.log("head", String(txt).slice(0, 200).replace(/\s+/g, " "));
  } catch (e) {
    const dt = nowMs() - t0;
    console.log("ERR", url);
    console.log("ms", dt);
    console.log(String(e && e.stack ? e.stack : (e && e.message ? e.message : e)));
  }
  console.log("----");
}

function runOneMax(url, timeoutMs, maxBytes) {
  const t0 = nowMs();
  try {
    const r = net.http.get(url, {
      responseType: "text",
      timeoutMs,
      maxBytes,
      followRedirects: true,
    });

    const txt = r.text();
    const dt = nowMs() - t0;

    console.log("OK", url);
    console.log("status", r.status, "ms", dt, "maxBytes", maxBytes, "bytes", typeof txt === "string" ? txt.length : -1);
    console.log("head", String(txt).slice(0, 200).replace(/\s+/g, " "));
  } catch (e) {
    const dt = nowMs() - t0;
    console.log("ERR", url);
    console.log("ms", dt, "maxBytes", maxBytes);
    console.log(String(e && e.stack ? e.stack : (e && e.message ? e.message : e)));
  }
  console.log("----");
}

// API-level tests (sync)
runOne("https://google.com", 10000);
runOne("https://dantri.com.vn", 10000);
runOne("http://dantri.com.vn", 10000);

// Should return quickly even if server is slow / keeps streaming
runOneMax("https://google.com", 10000, 100);
runOneMax("https://dantri.com.vn", 10000, 100);
runOneMax("http://dantri.com.vn", 10000, 100);
