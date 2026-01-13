import { net } from "qjsp:index.js";

if (typeof fetch !== "function") throw new Error("fetch not installed");

if (typeof globalThis.HttpRequestAsync !== "function") {
  console.log("repl fetch async test skipped (HttpRequestAsync not available)");
} else {
  const url = "https://example.com";
  const r = await fetch(url, { timeoutMs: 2000, followRedirects: true });
  if (typeof r.status !== "number") throw new Error("missing status");
  if (r.status < 200 || r.status >= 500) throw new Error(`unexpected status: ${r.status}`);
  const t = await r.text();
  if (typeof t !== "string" || t.length === 0) throw new Error("empty body");
  console.log("repl fetch async test OK", r.status);
}

void net;
