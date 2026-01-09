import { net } from "qjsp:index.js";

if (typeof fetch !== "function") throw new Error("fetch not installed");

const url = "https://example.com";

const r1 = await fetch(url, { timeoutMs: 10000, followRedirects: true });
if (typeof r1.status !== "number") throw new Error("missing status");
if (r1.status < 200 || r1.status >= 500) throw new Error(`unexpected status: ${r1.status}`);
const t1 = await r1.text();
if (typeof t1 !== "string" || t1.length === 0) throw new Error("empty body");

const n = 5;
const rs = await Promise.all(Array.from({ length: n }, () => fetch(url, { timeoutMs: 10000, followRedirects: true })));
for (const r of rs) {
  if (typeof r.status !== "number") throw new Error("missing status");
  if (r.status < 200 || r.status >= 500) throw new Error(`unexpected status: ${r.status}`);
}

if (typeof globalThis.HttpRequestAsync === "function") {
  console.log("stdjs fetch test OK (async)", r1.status, "concurrent=", n);
} else {
  console.log("stdjs fetch test OK (sync fallback)", r1.status, "concurrent=", n);
}

void net;
