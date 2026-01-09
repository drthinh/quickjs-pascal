import { net } from "qjsp:index.js";

// Requires internet access.
const r = net.http.get("https://example.com", { responseType: "text", timeoutMs: 10000 });

if (typeof r.status !== "number") throw new Error("missing status");
if (r.status < 200 || r.status >= 500) throw new Error(`unexpected status: ${r.status}`);

const txt = r.text();
if (typeof txt !== "string" || txt.length === 0) throw new Error("empty body");

console.log("stdjs http test OK", r.status);
